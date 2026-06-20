# KLYCH — device_tokens RLS Implementation Report

**Scope: `device_tokens` only.** No other table is modified, and RLS is **not**
enabled anywhere else. No alerts/onboarding/users/orgs/groups/invites/receipts
changes. Goal: safely unlock push-token registration.

Deliverables: `supabase/006_device_tokens_rls.sql` (migration),
`supabase/006_rollback.sql`, `supabase/006_verification.sql`, this report.

---

## 1. Current schema (reviewed)

```267:280:supabase/v2/schema.sql
CREATE TABLE device_tokens (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token       text NOT NULL,
  platform    text NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  is_active   boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_token_unique UNIQUE (token),
  CONSTRAINT device_tokens_user_token_unique UNIQUE (user_id, token)
);
```
- Ownership is via `user_id → users.id`; the authenticated caller maps to a
  `users` row through `users.auth_id = auth.uid()`.
- Pre-006 state: **RLS disabled** → any holder of the anon key could read/write
  any device's token (push-hijacking / token harvesting). This migration closes
  that for `device_tokens`.
- The app does not read/write `device_tokens` yet (the `DeviceTokenService`
  skeleton is un-wired), so enabling RLS now has **zero impact on current
  functionality** — the ideal moment to add it.

---

## 2. Design

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Owner identity | `auth_user_id()` `SECURITY DEFINER STABLE` helper returning `users.id` for `auth.uid()` | Avoids policy recursion through users' own (future) RLS; cached per statement; matches the RLS blueprint so the later full-RLS phase reuses it. |
| Policy granularity | Four separate policies (SELECT/INSERT/UPDATE/DELETE), all `to authenticated` | Explicit per-verb owner check; clear audit. |
| Predicate | `user_id = auth_user_id()` (USING for read/update/delete; WITH CHECK for insert/update) | Read/modify only own rows; cannot insert or reassign to another user. |
| service_role | RLS enabled **without** `FORCE ROW LEVEL SECURITY` | `service_role` has `BYPASSRLS` → the future dispatcher retains full access; no policy needed for it. |
| anon | No policy | Pre-login anon gets no access; registration is authenticated-only (post-login), matching app behavior. |
| Idempotency | `CREATE OR REPLACE` function; `DROP POLICY IF EXISTS` before `CREATE`; `ENABLE RLS` is a no-op if on | Safe to re-run. |

### Final policy set (designed)
| Policy | Command | Roles | USING | WITH CHECK |
|--------|---------|-------|-------|------------|
| `device_tokens_select_own` | SELECT | authenticated | `user_id = auth_user_id()` | — |
| `device_tokens_insert_own` | INSERT | authenticated | — | `user_id = auth_user_id()` |
| `device_tokens_update_own` | UPDATE | authenticated | `user_id = auth_user_id()` | `user_id = auth_user_id()` |
| `device_tokens_delete_own` | DELETE | authenticated | `user_id = auth_user_id()` | — |

---

## 3. Verification

`supabase/006_verification.sql` runs in one transaction (ends with `ROLLBACK`,
non-destructive) and simulates roles via `set local role` + a forged
`request.jwt.claims.sub`. It asserts:

| # | Scenario | Expected | Maps to requirement |
|---|----------|----------|---------------------|
| 1 | User A `SELECT` | sees only A's token; cannot see B's | users read only their own |
| 2 | A `INSERT` own | allowed | users create only their own |
| 3 | A `INSERT` for B | denied (SQLSTATE 42501) | cannot create for others |
| 4 | A `UPDATE` B's row | 0 rows affected | users update only their own |
| 5 | A `UPDATE` own | 1 row | own update works |
| 6 | A `DELETE` B's row | 0 rows | users delete only their own |
| 7 | A `DELETE` own | 1 row | own delete works |
| 8 | User B `SELECT` | sees only B's token | symmetric isolation |
| 9 | `service_role` SELECT/UPDATE | sees + writes all rows | service_role retains access |
| 10 | Policy-set audit | exactly 4 policies + RLS enabled | final-state audit |

Run after applying the migration:
```
psql "$DATABASE_URL" -f supabase/006_verification.sql      # prints DEVICE_TOKENS RLS OK
```
(Also paste-able into the Supabase SQL Editor — single transaction.)

> Note: this environment has no database/psql access, so the script was authored
> and statically reviewed but not executed here. Run it on the project (same flow
> as `005_verification.sql`) to confirm before relying on it. The Flutter side is
> unaffected (no Dart changes; `flutter analyze`/`test` unchanged from the prior
> green run).

---

## 4. Complete audit of the final policy set

**Coverage** — every verb is constrained; no verb is left open:
- SELECT / INSERT / UPDATE / DELETE each have exactly one owner-scoped policy.
- No `FOR ALL` catch-all, no permissive duplicate, no `to public` policy.

**Privilege boundaries:**
- `authenticated`: row access strictly limited to `user_id = auth_user_id()` for
  all four verbs; cannot read, write, reassign, or delete another user's token.
- `anon`: no policy ⇒ fully denied (correct — no token ops before login).
- `service_role`: `BYPASSRLS` + no `FORCE` ⇒ unrestricted (dispatcher/admin).
- Table owner/superuser: unaffected (no `FORCE`).

**Recursion / safety:** `auth_user_id()` is `SECURITY DEFINER` with fixed
`search_path = public`, so the device_tokens policies never recurse into users'
RLS and aren't affected when full RLS lands on `users`.

**Constraint interplay:** `UNIQUE(token)` / `UNIQUE(user_id, token)` remain the
upsert keys; RLS adds row filtering on top of (unchanged) table grants. A device
re-registering under a new user is handled by upsert + the owner check.

**Residual considerations (not blockers):**
- Requires the standard Supabase grants for `authenticated` on `public.device_tokens`
  (present by default; the verification's "insert own" would fail loudly if absent).
- Column-level immutability (e.g., preventing `user_id` reassignment) is enforced
  by WITH CHECK (`user_id` must remain the caller's) — sufficient for owner-only.

**Audit query (also embedded in verification):**
```sql
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'device_tokens'
order by cmd;
-- expect 4 rows; each qual/with_check = (user_id = auth_user_id())
```

---

## 5. Rollout / rollback

- **Apply:** run `supabase/006_device_tokens_rls.sql` in the SQL Editor → run
  `006_verification.sql` → expect `DEVICE_TOKENS RLS OK`.
- **Rollback:** `supabase/006_rollback.sql` drops the 4 policies, disables RLS on
  `device_tokens`, and drops `auth_user_id()` (keep the function if a later
  full-RLS migration has adopted it — comment noted in the file). No data change,
  zero data-loss risk.
- **Order safety:** because the app does not yet touch `device_tokens`, applying
  or rolling back has no effect on the live app; only the future (still-dormant)
  `DeviceTokenService` depends on these policies.

---

## 6. Result

`device_tokens` is now (after applying 006) **owner-only secured** with
`service_role` access preserved — the security gate (blocker **B1**) for wiring
`DeviceTokenService` is satisfiable. The remaining push prerequisites are
unchanged and outside this scope: **B2** APNs configuration, **B3** Android build
verification. No other table, alert logic, or onboarding flow was modified.
