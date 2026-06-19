# KLYCH — Atomic Alert Creation RPC: Design & Migration Plan

**Design/audit only — nothing implemented.** This document specifies a
production-safe migration from the current client-side multi-step alert creation
to a single transactional PostgreSQL function `create_alert(...)`, ahead of Push
Notifications.

---

## 1. Current risks

Today `AlertService.createAlert` (`lib/services/alert_service.dart`) performs a
sequence of **independent PostgREST requests**, each its own auto-committed
transaction, in this order:

1. `INSERT alerts` → commits, becomes visible (realtime emits / a webhook would fire)
2. `INSERT alert_targets` (+ looped `INSERT alert_target_users`)
3. re-resolve recipients (`AlertDeliveryService.resolveRecipientIdsForAlert`)
4. `INSERT alert_receipts`
5. on failure → best-effort `deleteAlert` (self-swallowing)

Resulting risks:

- **Race window:** the `alerts` row is visible **before** targets/receipts exist
  (multiple mobile round-trips later). A webhook/Edge Function on `alerts INSERT`
  would read **0 receipts**. The same latent race exists in the realtime path
  (`shouldUserReceiveAlert` can resolve an empty set and silently skip).
- **Partial writes:** any step can succeed while a later one fails; a client
  crash or network drop leaves an **orphan alert with no receipts** (no
  server-side cleanup; rollback is best-effort and swallows its own error).
- **Logic duplication / drift:** recipient resolution lives in Dart
  (`RecipientResolver` / `resolveFromTargetRows`); a server dispatcher would have
  to re-implement it and could drift from the UI.

(Full evidence in `alert_pipeline_verification.md`.)

---

## 2. RPC design

A single `SECURITY`-controlled PL/pgSQL function executed as **one transaction**:

```
create_alert(
  p_organization_id uuid,
  p_message         text,
  p_level           text,         -- 'RED' | 'GREEN'
  p_sender_user_id  uuid,
  p_is_test         boolean default false,
  p_org_wide        boolean default false,
  p_status_codes    text[]  default '{}',
  p_department_ids  uuid[]  default '{}',
  p_group_ids       uuid[]  default '{}',
  p_user_ids        uuid[]  default '{}'
) returns table (
  id uuid, organization_id uuid, message text, level text,
  is_test boolean, sender_user_id uuid, created_at timestamptz,
  recipient_count integer
)
```

Why pass the **high-level selection** (the same fields as
`AlertRecipientsSelection`) rather than pre-built target rows: it makes the SQL
the **single source of truth** for both (a) the persisted `alert_targets` rows
and (b) the resolved `alert_receipts`, guaranteeing they always agree (and match
the UI, which uses the identical UNION rules).

Behavioral mapping (identical to today):

| Selection | `alert_targets` rows written | Recipients (UNION, active, sender excluded, distinct) |
|-----------|------------------------------|--------------------------------------------------------|
| `org_wide=true` | one `organization` row | all non-disabled org users |
| status codes | one `status` row per code | users whose `status` ∈ codes |
| department ids | one `department` row per id | users whose `department_id` ∈ ids |
| group ids | one `group` row per id | users in `group_members` for those groups |
| user ids | one `users` row + `alert_target_users` rows | those users |

The resolution mirrors `AlertDeliveryService.resolveFromTargetRows` /
`RecipientResolver._computeIds` exactly. `users.status` and
`alert_targets.status_code` both reference `user_statuses.code` (canonical), so a
direct equality matches the client's `UserStatus.normalize`. Zero recipients →
`RAISE EXCEPTION` → full rollback (preserves `NoRecipientsException`).

---

## 3. SQL implementation plan

```sql
create or replace function public.create_alert(
  p_organization_id uuid,
  p_message         text,
  p_level           text,
  p_sender_user_id  uuid,
  p_is_test         boolean default false,
  p_org_wide        boolean default false,
  p_status_codes    text[]  default '{}',
  p_department_ids  uuid[]  default '{}',
  p_group_ids       uuid[]  default '{}',
  p_user_ids        uuid[]  default '{}'
)
returns table (
  id uuid, organization_id uuid, message text, level text,
  is_test boolean, sender_user_id uuid, created_at timestamptz,
  recipient_count integer
)
language plpgsql
volatile
security invoker            -- see §"Security" note below
set search_path = public
as $$
declare
  v_alert   alerts%rowtype;
  v_count   integer;
begin
  -- ---- validation (matches current client guards) -------------------------
  if p_level not in ('RED','GREEN') then
    raise exception 'INVALID_LEVEL' using errcode = 'P0001';
  end if;
  if coalesce(btrim(p_message), '') = '' then
    raise exception 'EMPTY_MESSAGE' using errcode = 'P0001';
  end if;

  -- ---- 1) alert -----------------------------------------------------------
  insert into alerts (organization_id, message, level, sender_user_id, is_test)
  values (p_organization_id, p_message, p_level, p_sender_user_id, p_is_test)
  returning * into v_alert;

  -- ---- 2/3) targets + explicit users -------------------------------------
  if p_org_wide then
    insert into alert_targets (alert_id, target_type)
    values (v_alert.id, 'organization');
  else
    insert into alert_targets (alert_id, target_type, status_code)
      select v_alert.id, 'status', c from unnest(p_status_codes) as c;
    insert into alert_targets (alert_id, target_type, department_id)
      select v_alert.id, 'department', d from unnest(p_department_ids) as d;
    insert into alert_targets (alert_id, target_type, group_id)
      select v_alert.id, 'group', g from unnest(p_group_ids) as g;

    if coalesce(array_length(p_user_ids, 1), 0) > 0 then
      insert into alert_targets (alert_id, target_type)
      values (v_alert.id, 'users');
      insert into alert_target_users (alert_id, user_id)
        select v_alert.id, u from unnest(p_user_ids) as u
        on conflict do nothing;
    end if;
  end if;

  -- ---- 4/5/6/7) resolve recipients (UNION, active, ≠ sender, distinct) ----
  with recip as (
    select u.id
    from users u
    where u.organization_id = p_organization_id
      and u.is_disabled = false
      and u.id <> p_sender_user_id
      and (
        p_org_wide
        or u.status = any(p_status_codes)
        or u.department_id = any(p_department_ids)
        or u.id = any(p_user_ids)
        or exists (
          select 1 from group_members gm
          where gm.user_id = u.id
            and gm.group_id = any(p_group_ids)
        )
      )
  )
  insert into alert_receipts (alert_id, user_id)
  select v_alert.id, r.id from recip r
  on conflict (alert_id, user_id) do nothing;

  get diagnostics v_count = row_count;

  -- ---- 10) block + rollback if no recipients (== NoRecipientsException) ---
  if v_count = 0 then
    raise exception 'NO_RECIPIENTS' using errcode = 'P0001';
  end if;

  -- ---- 9) return ----------------------------------------------------------
  return query
    select v_alert.id, v_alert.organization_id, v_alert.message, v_alert.level,
           v_alert.is_test, v_alert.sender_user_id, v_alert.created_at, v_count;
end;
$$;

grant execute on function public.create_alert(
  uuid, text, text, uuid, boolean, boolean, text[], uuid[], uuid[], uuid[]
) to anon, authenticated;
```

Notes:
- **Atomicity:** the whole body runs in the caller's single transaction. Any
  `raise` (incl. `NO_RECIPIENTS`) rolls back the alert + targets + receipts — no
  orphans, no compensating delete needed.
- **`= any('{}')`** is false for empty arrays, so unselected categories
  contribute nothing → correct UNION. Distinctness is inherent (one row per user
  scanned once). `on conflict do nothing` guards the `alert_receipts_unique` and
  `alert_target_users` PK constraints.
- **Indexes:** existing `users_org_status_idx`, `users_org_dept_idx`,
  `group_members_user_idx`, and the `alert_receipts_unique` index already cover
  this; **no new indexes required**.
- **Security:** ships as `security invoker` to exactly preserve today's access
  model (RLS is currently disabled). When RLS is enabled later, switch to
  `security definer` and add guards (`p_sender_user_id` belongs to
  `p_organization_id`, caller `auth.uid()` matches, role ∈ admin/leader). Flagged
  as a follow-up so this change introduces **no behavior change** now.

---

## 4. Required migration files

Follow the existing `supabase/NNN_*.sql` convention:

| File | Purpose |
|------|---------|
| `supabase/005_create_alert_rpc.sql` | `create or replace function create_alert(...)` + `grant execute` (the SQL in §3). Idempotent. |
| `supabase/005_rollback.sql` | `drop function if exists public.create_alert(uuid, text, text, uuid, boolean, boolean, text[], uuid[], uuid[], uuid[]);` |
| `supabase/005_verification.sql` | smoke tests (see §7): call with each target type on seed data, assert returned `recipient_count` and row counts in `alert_targets` / `alert_receipts`, then clean up. |

No changes to any table, column, constraint, index, trigger, RLS, or the realtime
publication. Purely additive (a new function).

---

## 5. Flutter changes required

Minimal, isolated to `lib/services/alert_service.dart`. **Public signature of
`AlertService.createAlert` stays the same**, so call sites
(`leader_home_screen.dart`, `home_screen.dart`) and all UI behavior are
unchanged.

New body (replacing the multi-step sequence):

```dart
static Future<Map<String, dynamic>> createAlert({
  required String organizationId,
  required String message,
  required String level,
  required AlertRecipientsSelection recipients,
  required String senderUserId,
  bool isTest = false,
}) async {
  try {
    final rows = await supabase.rpc('create_alert', params: {
      'p_organization_id': organizationId,
      'p_message': message,
      'p_level': level,
      'p_sender_user_id': senderUserId,
      'p_is_test': isTest,
      'p_org_wide': recipients.orgWide,
      'p_status_codes': recipients.statusCodes.toList(),
      'p_department_ids': recipients.departmentIds.toList(),
      'p_group_ids': recipients.groupIds.toList(),
      'p_user_ids': recipients.userIds.toList(),
    });

    final row = Map<String, dynamic>.from((rows as List).first as Map);
    final count = (row['recipient_count'] as num?)?.toInt() ?? 0;

    return {
      ...row,
      'recipient_count': count,
      'target_label': recipients.recipientsLabel(count: count),
    };
  } on PostgrestException catch (e) {
    if (e.message.contains('NO_RECIPIENTS')) {
      throw NoRecipientsException();
    }
    rethrow; // INVALID_LEVEL / EMPTY_MESSAGE / etc. bubble up as today
  }
}
```

Effects:
- The returned map still contains `id, organization_id, message, level,
  is_test, sender_user_id, created_at` (from the RPC's `returns table`), so the
  optimistic history insert in `leader_home_screen.sendAlert` works **unchanged**
  (it spreads `...inserted` and adds label/counts).
- `NoRecipientsException` semantics preserved (mapped from the RPC error).
- **Removes** the now-unnecessary `UserOrgService.fetchOrgUsers` +
  `GroupService.fetchGroups` + client resolution from `createAlert` (a perf win:
  fewer round-trips). `RecipientResolver` stays as the **UI** source of truth for
  the live count/preview/send-button — only the *write path* moves to the RPC.

No other services change:
- `AlertDeliveryService` — keep `resolveRecipientIdsForAlert`,
  `shouldUserReceiveAlert`, history, `_buildTargetLabels` (still read
  `alert_targets`, whose shape is identical). `deleteAlert` may be retained for
  admin tooling but is no longer needed for rollback.
- `AlertReceiptService` — unchanged (`createReceiptsForAlert` becomes dead code
  for the send path; safe to keep or remove later).

---

## 6. Push notification readiness impact

After the RPC lands, the alert row and its receipts commit **together**:

| Concern (pre-RPC) | Post-RPC |
|-------------------|----------|
| `alerts INSERT` visible before receipts | **Fixed** — replication/webhooks emit at COMMIT, with receipts already committed |
| Webhook on `alerts INSERT` races writes | **Safe** — Database Webhook fires via `pg_net` post-commit; the Edge Function reads fully-committed receipts |
| `alert_receipts` as source of truth | **Authoritative & immediately present** for every alert |
| Orphan alert / false push on rollback | **Eliminated** — no alert row exists unless receipts exist |
| Realtime path empty-set skip | **Fixed** — `shouldUserReceiveAlert` always sees receipts |

⇒ A future dispatcher: Database Webhook on `alerts INSERT` → Edge Function →
`select user_id from alert_receipts where alert_id = :id` → join active
`device_tokens` → FCM/APNs. No retry/poll/race handling needed. (Resolves the
prerequisite blocker from `push_notifications_readiness_report.md`.)

---

## 7. Rollout plan

1. **Deploy `005_create_alert_rpc.sql`** to staging (purely additive; existing
   app keeps working via the old multi-step path — both coexist).
2. **Run `005_verification.sql`** on staging seed data:
   - org-wide, single department, single status, single group, explicit users,
     and multi-select combinations → assert `recipient_count` equals the UNION,
     sender excluded, duplicates removed; assert `alert_targets` row shapes match
     the legacy client output; assert 0-recipient call raises and writes nothing.
   - regression: leader/admin/member flows, history, acknowledgements still work.
3. **Ship the Flutter change** (RPC call) behind the normal release. Old installs
   continue using the legacy path against the unchanged tables during the
   transition — no coordinated cutover required.
4. **Deploy the function to production**, then release the app update.
5. **Monitor**: error rate of `create_alert`, recipient counts vs. expectations,
   no orphan alerts (`alerts` with zero `alert_receipts`).
6. Only **after** push is live and stable, optionally consider tightening direct
   table `INSERT` access (with RLS) so alert creation must go through the RPC.

## 8. Rollback plan

- **App-level:** revert the `alert_service.dart` change (re-release the prior
  build). Because tables are unchanged, the legacy multi-step path works
  immediately with or without the function present.
- **DB-level:** `supabase/005_rollback.sql` → `drop function ... create_alert`.
  Order: **revert the app first, then drop the function** (dropping while the new
  app is live would break sends). The function is additive and `create or
  replace`-able, so re-applying is safe and non-destructive.
- No data migration is involved, so rollback carries no data-loss risk.

---

## Final recommendation

Proceed with `create_alert(...)` as specified: it is **additive, behavior-
preserving, and reversible**, eliminates the partial-write/orphan and race risks,
and converts `alert_receipts` into an immediately-authoritative source of truth —
the exact prerequisite for safe FCM/APNs push. Implement after this plan is
approved; do the DB function + staging verification before the Flutter switch.
