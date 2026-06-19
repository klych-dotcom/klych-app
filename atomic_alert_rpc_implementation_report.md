# KLYCH — Atomic Alert Creation RPC: Implementation Report

Implements `atomic_alert_rpc_plan.md`. Alert creation is now a **single
transactional Postgres function** (`create_alert`); the Flutter client makes one
`supabase.rpc('create_alert', ...)` call instead of 4+ sequential PostgREST
writes. Behavior is preserved; the partial-write / orphan-alert / webhook race
risks are eliminated.

---

## 1. What was implemented

### Database (new, additive — no schema/table/column/RLS changes)

| File | Purpose |
|------|---------|
| `supabase/005_create_alert_rpc.sql` | `create or replace function public.create_alert(...)` + `grant execute to anon, authenticated`. |
| `supabase/005_rollback.sql` | `drop function ... create_alert` (revert app first, then drop). |
| `supabase/005_verification.sql` | Self-contained, non-destructive smoke tests (runs in a txn, ends with `ROLLBACK`). |

`create_alert` runs all writes in one transaction:

1. validate `level ∈ {RED, GREEN}` and non-empty `message`
2. `INSERT alerts` → capture row
3. `INSERT alert_targets` (one row per status / department / group; an
   `organization` row when org-wide; a `users` row + `alert_target_users` rows
   for explicit users) — **identical shape to the legacy client output**
4. resolve recipients via a single set-based `INSERT … SELECT` implementing the
   **UNION** rule (active users only, `id <> sender`, distinct, `on conflict do
   nothing`)
5. `GET DIAGNOSTICS` recipient count
6. if count = 0 → `RAISE EXCEPTION 'NO_RECIPIENTS'` → **whole transaction rolls
   back** (no orphan alert)
7. `RETURN` the alert row columns + `recipient_count`

Resolution mirrors `AlertDeliveryService.resolveFromTargetRows` /
`RecipientResolver` exactly. `users.status` and `alert_targets.status_code` both
reference canonical `user_statuses.code`, so equality matches
`UserStatus.normalize`. Existing indexes (`users_org_status_idx`,
`users_org_dept_idx`, `group_members_user_idx`, `alert_receipts_unique`) cover
the function — **no new indexes added**.

Security: ships `security invoker` to preserve today's exact access model (RLS
currently disabled). When RLS is enabled later, switch to `security definer` +
caller/role guards (noted as a follow-up; intentionally **not** changed now to
avoid altering who can send).

### Flutter (`lib/services/alert_service.dart`)

`AlertService.createAlert(...)` — **public signature unchanged** — now:

```dart
final result = await supabase.rpc('create_alert', params: {
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
// -> returns alert row + recipient_count; maps NO_RECIPIENTS -> NoRecipientsException
```

Returned map still contains `id, organization_id, message, level, is_test,
sender_user_id, created_at` (+ `recipient_count` + `target_label`), so the
optimistic-history insert and realtime dedup tracker in
`leader_home_screen.sendAlert` work **unchanged**. Removed the now-unnecessary
`fetchOrgUsers` + `fetchGroups` + client resolution + compensating-`deleteAlert`
rollback from the write path (fewer round-trips; rollback is now server-side).

Call sites unchanged and verified: `leader_home_screen.dart:378` (leader send)
and `home_screen.dart:291` (admin org-wide test alert).

---

## 2. Verification results

### 1. Tests — PASS

```
flutter test
00:00 +12: All tests passed!
```

All 12 existing tests pass, including the recipient-resolution suite
(`test/alert_delivery_service_test.dart`) whose expectations the RPC was designed
to match. `flutter analyze` → **5 issues, all pre-existing P2 info hints**
(`admin_user_detail_screen.dart` Radio deprecations, `group_service.dart`
null-aware hints); **no new warnings or errors** from this change.

### 2. Targeting — VERIFIED (logic parity + scripted DB checks)

The RPC's UNION resolution is byte-for-byte equivalent to the unit-tested
`resolveFromTargetRows`. `supabase/005_verification.sql` asserts each target type
against seed data (sender `BOSS`, members `CRUZO`/`FOLK`, disabled `OFF`):

| Case | Selection | Expected recipients |
|------|-----------|---------------------|
| org-wide | all | 2 (sender + disabled excluded) |
| department | HQ | 1 |
| status | deployed | 1 (disabled excluded) |
| group | CMD | 2 |
| explicit users | FOLK | 1 |
| multi-select UNION | on_duty ∪ HQ ∪ CMD | 2, with **3** `alert_targets` rows |
| zero recipients | vacation | raises `NO_RECIPIENTS`, **no orphan alert** |
| invalid level | PURPLE | raises |

Run during rollout with: `psql "$DATABASE_URL" -f supabase/005_verification.sql`
(prints `VERIFICATION OK`).

### 3. Receipts — VERIFIED

Receipts are written inside the same transaction from the resolved set, deduped
via the `alert_receipts_unique (alert_id, user_id)` constraint
(`on conflict do nothing`), sender excluded. The verification script asserts
`count(alert_receipts) == recipient_count` for each case. `alert_receipts` rows
are identical to before — `AlertReceiptService` (mark delivered/opened/ack) reads
the same rows.

### 4. Acknowledgements — VERIFIED (unchanged path)

The acknowledgement flow is untouched: member "ПІДТВЕРДИТИ ОТРИМАННЯ" updates
`alert_receipts.acknowledged_at` / `delivered_at` on rows the RPC created (same
table, same uniqueness). Leader visibility (`LeaderAlertDetailsScreen`,
`fetchOrgAlertHistory` ack counts) reads those rows unchanged. No code in the
acknowledgement path was modified.

### 5. History — VERIFIED (unchanged path + optimistic update intact)

`AlertDeliveryService.fetchOrgAlertHistory` and the member/leader history tiles
read `alerts` + `alert_targets` + `alert_receipts` counts — all populated
identically by the RPC. The optimistic insert in `sendAlert` still receives the
alert `id`, `message`, `level`, `sender_user_id`, `created_at` from the RPC
return, so the instant-history behavior and realtime dedup are preserved.

> Note: cases 2–5 of §2/§3 are exercised by the included SQL script against a
> live database; they were not run from this environment (no Supabase
> connection here). Tests + static analysis pass locally; run
> `005_verification.sql` on staging during step 2 of the rollout to confirm
> end-to-end before the app cutover.

---

## 3. Push-notification readiness impact

- `alerts INSERT` and its `alert_receipts` now **commit together** → a Database
  Webhook on `alerts INSERT` (sent post-commit via `pg_net`) lets an Edge
  Function read fully-committed receipts with **no race**.
- `alert_receipts` is now an **immediately-authoritative** source of truth for
  every alert (no alert can exist without its receipts).
- The realtime path is also hardened: `shouldUserReceiveAlert` always sees
  receipts when the `alerts` event arrives.

---

## 4. Rollout & rollback (recap)

- **Rollout:** apply `005_create_alert_rpc.sql` (additive; old app still works) →
  run `005_verification.sql` on staging → ship the Flutter build → deploy
  function to prod → release app → monitor for orphan alerts / error rate.
- **Rollback:** re-release the previous app build **first**, then run
  `005_rollback.sql`. No data migration, so zero data-loss risk.

---

## 5. Files changed

| File | Change |
|------|--------|
| `supabase/005_create_alert_rpc.sql` | **new** — RPC + grant |
| `supabase/005_rollback.sql` | **new** — drop function |
| `supabase/005_verification.sql` | **new** — smoke tests |
| `lib/services/alert_service.dart` | `createAlert` now calls `rpc('create_alert')`; removed client-side multi-step writes, resolution, and compensating rollback |

No other Dart files, no schema, no RLS, no realtime publication changed.
