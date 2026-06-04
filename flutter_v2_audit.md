# KLYCH Flutter ↔ Supabase v2 Compatibility Audit

**Date:** 2026-05-31  
**Database:** Fresh Supabase v2 project (schema + seed deployed)  
**Scope:** All Dart code under `lib/` and `test/` — audit only, no code changes  
**Reference:** `supabase/v2/schema.sql`, `supabase/v2/migration_plan.md`

---

## Executive summary

The Flutter app is still written against the **v1 column names and invite shape**. On the live v2 database, most authenticated flows will fail immediately with PostgREST errors (`PGRST204` unknown column, `23502` NOT NULL violation).

| Area | v2 readiness |
|------|--------------|
| Auth cold start / login | **Broken** — selects removed `users.permission` |
| Create organization | **Broken** — invalid user insert fields |
| Invite create / redeem | **Broken** — `invites.permission`, missing `expires_at` |
| Alerts send / receive | **Broken** — wrong insert columns; UI reads `type` not `level` |
| Departments / groups / status | **Mostly compatible** |
| User org management | **Partially broken** — writes `permission` on role update |
| Realtime subscriptions | **Structurally OK** — depend on above inserts working |
| v2-only tables | **Not wired** — receipts, targets, redemptions, audit, FCM |

There is **no repository layer**; all DB access goes through **4 services** and **inline Supabase calls in screens**.

---

## Critical issues

These will cause runtime failures against v2 **today**.

| # | Issue | Error type | Impact |
|---|-------|------------|--------|
| C1 | `users.permission` selected in `main.dart`, `login_screen.dart`, `user_org_service.dart` | PostgREST column not found | Cold start routing and login fail for any existing user |
| C2 | `UserRole.toDbFields()` writes `permission` on every user insert/update | PostgREST column not found | Registration, invite join, admin role change all fail |
| C3 | `invites` insert uses `permission` instead of `role`; omits required `expires_at` | Column not found + NOT NULL violation | Admin home cannot create or load invites |
| C4 | `AlertService.createAlert()` inserts `type`, `created_by`, `created_by_name` | Column not found | All alert sends fail (admin + leader) |
| C5 | Alert UI reads `alert['type']` but v2 returns `level` | Silent logic bug | Even after insert fix, RED/GREEN detection and siren routing break |
| C6 | `create_server_screen.dart` inserts `name` on `users` | Column not found | New org registration fails at admin user insert |

---

## Breaking schema mismatches

### Removed / renamed columns still used by Flutter

| v1 (Flutter) | v2 (schema) | Files using v1 |
|--------------|-------------|----------------|
| `users.permission` | **removed** — use `role` only | `main.dart`, `login_screen.dart`, `user_org_service.dart`, `user_role.dart`, `create_server_screen.dart`, `invite_join_screen.dart` |
| `users.name` | **removed** — use `callsign` / `display_name` | `create_server_screen.dart` |
| `invites.permission` | **renamed** → `invites.role` | `home_screen.dart`, `invite_join_screen.dart` |
| `alerts.type` | **renamed** → `alerts.level` | `alert_service.dart`, `alert_utils.dart` (callers), `leader_home_screen.dart`, `member_home_screen.dart`, `alert_screen.dart` |
| `alerts.created_by` (auth uuid) | **renamed** → `alerts.sender_user_id` (`users.id` FK) | `alert_service.dart`, `alert_delivery_tracker.dart` |
| `alerts.created_by_name` | **removed** — join `users.callsign` | `alert_service.dart`, `member_home_screen.dart` (local test) |
| `alerts.target` (inline) | **removed** — `alert_targets` + `alert_target_users` | Not inserted (OK); UI still references `alert['target']` in history |

### Required v2 columns never sent by Flutter

| Table | Required / important column | Flutter status |
|-------|----------------------------|----------------|
| `invites` | `expires_at` NOT NULL | Never set on insert |
| `invites` | `max_uses`, `use_count`, `revoked_at` | Never read or written |
| `invites` | `role` NOT NULL | Uses `permission` instead |
| `alerts` | `level` NOT NULL | Sends `type` instead |
| `alerts` | `sender_user_id` | Sends auth uuid as `created_by` |
| `invite_redemptions` | Full redemption audit | Never inserted |
| `alert_targets` | Target resolution | Never inserted |
| `alert_receipts` | Delivery / ack tracking | Never used |

### Compatible (no schema mismatch)

| Table / feature | Notes |
|-----------------|-------|
| `organizations` | Insert/select shape matches |
| `departments` | CRUD matches; archive flag used correctly |
| `operational_groups` | CRUD matches; `created_by` uses `users.id` ✓ |
| `group_members` | Insert/delete matches; optional `added_by` not sent |
| `users.status` | Values match `user_statuses` seed |
| `users.role` | Values `admin`/`leader`/`member` match CHECK |
| `users.department_id`, `is_disabled`, `last_activity_at` | Used correctly |

---

## Flow-by-flow verification

### 1. Create organization (`create_server_screen.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Auth signUp | — | OK | ✓ |
| Insert `organizations` | `name`, `owner_id` | OK | ✓ |
| Seed departments | RPC `seed_org_departments(org_id)` | Client loop via `DepartmentService.seedDefaults()` — 6 names incl. "Evacuation" (v2 templates have 5) | ⚠ Works but wrong approach |
| Insert admin `users` row | `auth_id`, `callsign`, `role`, optional `department_id`, `status` | Sends `name`, `permission`, `callsign`, `role` | **FAIL** |

**Blockers:** `name`, `permission` columns.

---

### 2. Create invite (`home_screen.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Insert invite | `organization_id`, `code`, `role`, `expires_at`, optional `max_uses`, `created_by` | `organization_id`, `code`, `permission` only | **FAIL** |
| Load invites | Read `role`, filter active | Reads `permission` | **FAIL** |
| Regenerate code | Update by `organization_id` + `role` | `.eq('permission', …)` | **FAIL** |

**Blockers:** `permission` column, missing `expires_at`.

---

### 3. Redeem invite (`invite_join_screen.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Lookup invite | `role`, validate `expires_at`, `revoked_at`, `use_count < max_uses` | Reads `permission`; no validation | **FAIL** + security gap |
| Auth signUp | — | OK | ✓ |
| Insert `users` | `role` only (no permission) | `toDbFields()` adds `permission` | **FAIL** |
| Member department | Required by CHECK | Required in UI — OK if departments loaded | ⚠ UX |
| Insert `invite_redemptions` | Expected | Not done | Missing |
| Increment `use_count` | Expected | Not done | Missing |

**UX blocker:** Departments load only on `onEditingComplete` (keyboard Done), not on blur/paste — member registration appears broken even after schema fix.

**Leader path:** `department_id` optional in v2 — OK.

---

### 4. Login / session restore (`login_screen.dart`, `main.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Select user role | `select('role')` | `select('role, permission')` | **FAIL** |
| Route by role | `UserRole.authorizationRole` | Logic OK if query succeeds | ✓ |

---

### 5. Admin alerts (`home_screen.dart` → `alert_service.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Insert alert | `organization_id`, `level`, `message`, `sender_user_id`, `is_test` | `type`, `created_by`, `created_by_name` | **FAIL** |
| Insert `alert_targets` | At least org-wide target row | Not done | Missing (org-wide realtime still works if insert fixed) |
| Realtime receive | INSERT on `alerts` | Subscribed on leader/member screens | ✓ (if insert works) |
| RED vs GREEN | Read `level` | Reads `type` | **FAIL** after insert fix |
| Self-delivery skip | Compare `sender_user_id` to current `users.id` | Compares `created_by` to auth uuid | **FAIL** |

---

### 6. Leader alerts (`leader_home_screen.dart`)

Same as admin alerts via `AlertService.createAlert()`. Target dropdown is disabled (`AlertTargeting.serverSideEnabled = false`) — acceptable for Phase 1; delivery is org-wide via realtime filter.

History stored in **SharedPreferences**, not server — works offline but ignores v2 `alert_receipts`.

---

### 7. Member receiving alerts (`member_home_screen.dart`)

| Step | v2 expectation | Flutter actual | Status |
|------|----------------|----------------|--------|
| Realtime subscription | `alerts` INSERT filtered by `organization_id` | OK | ✓ |
| Level detection | `data['level']` | `data['type']` | **FAIL** |
| Acknowledgement | `alert_receipts` insert/update | Not implemented | Missing |
| History | Server receipts | SharedPreferences only | Legacy |

---

### 8. Group management (`groups_screen.dart`, `group_service.dart`)

| Operation | v2 | Flutter | Status |
|-----------|-----|---------|--------|
| List groups | ✓ | ✓ | ✓ |
| Create / rename / delete | ✓ | ✓ | ✓ |
| Add / remove members | ✓ | ✓ | ✓ |
| `added_by` on insert | Optional | Not sent | P4 |
| Cross-org trigger | DB enforced | N/A | ✓ |

**Verdict:** Compatible once user profile queries work (depends on C1 fix).

---

### 9. User status handling (`profile_screen.dart`, `leader_org_screen.dart`)

| Operation | v2 | Flutter | Status |
|-----------|-----|---------|--------|
| Status values | FK to `user_statuses` (5 codes) | `UserStatus.all` matches seed | ✓ |
| Update status | `users.status` + `last_activity_at` | OK via `UserOrgService` | ✓ |
| Realtime dashboard | `users` UPDATE by org | `UserOrgService.subscribeUserChanges` | ✓ |
| Profile load | — | Uses `userSelect` with `permission` | **FAIL** until C1 |

---

### 10. Organization management (users, departments)

| Feature | Status |
|---------|--------|
| `departments_screen.dart` CRUD | ✓ Compatible |
| `users_screen.dart` list | **FAIL** — select includes `permission` |
| `admin_user_detail_screen.dart` role update | **FAIL** — writes `permission` |
| `admin_user_detail_screen.dart` disable / delete | ✓ Compatible |
| Member without department (admin assigns) | DB CHECK rejects — UI allows null | ⚠ P3 validation gap |

---

## Models audit

| Model | v2 alignment | Issues |
|-------|--------------|--------|
| `user_role.dart` | Partial | `toDbFields()` dual-writes `permission`; `resolveRaw()` falls back to `permission` |
| `user_status.dart` | ✓ Full | Matches `user_statuses` seed |
| `alert_constants.dart` | ✓ Values | `RED`/`GREEN` match DB CHECK; field name in DB is `level` not `type` |
| `alert_targeting.dart` | Partial | Client targets (`medic`, `driver`) ≠ v2 `alert_targets.target_type`; server flag false |
| **Missing models** | — | No Dart models for `Invite`, `Alert`, `AlertReceipt`, `AlertTarget`, `Department` (raw maps used everywhere) |

---

## Services audit

| Service | Queries | Inserts/updates | v2 status |
|---------|---------|-----------------|-----------|
| `alert_service.dart` | — | Wrong alert columns | **P2 broken** |
| `user_org_service.dart` | Selects `permission` | `updateRole` writes `permission` | **P0/P3 broken** |
| `department_service.dart` | ✓ | ✓ | Compatible (seed method should use RPC — P4) |
| `group_service.dart` | ✓ embed `users` | ✓ | Compatible |

**No repositories exist** — pattern is service + inline screen queries.

---

## Realtime subscriptions audit

| Channel | Table | Event | Filter | v2 adjustment needed |
|---------|-------|-------|--------|------------------------|
| `leader-alerts-{orgId}` | `alerts` | INSERT | `organization_id` | None — works when alerts insert |
| `member-alerts-{orgId}` | `alerts` | INSERT | `organization_id` | None — works when alerts insert |
| `org-users-{orgId}` | `users` | UPDATE | `organization_id` | None |
| *(missing)* | `alert_receipts` | INSERT/UPDATE | org via join | Add when ack dashboard built |
| *(missing)* | `users` | INSERT | org | Optional for live user list |

Realtime publication in v2 includes `users`, `alerts`, `alert_receipts` — Flutter only subscribes to the first two.

---

## Files affected (complete inventory)

### P0 — App will not run

| File | Issue |
|------|-------|
| `lib/main.dart` | `select('role, permission')` |
| `lib/screens/login_screen.dart` | `select('role, permission')` |
| `lib/services/user_org_service.dart` | `userSelect` includes `permission`; blocks all profile/org user loads |
| `lib/models/user_role.dart` | `toDbFields()` writes removed column (blocks writes everywhere) |

### P1 — Registration broken

| File | Issue |
|------|-------|
| `lib/screens/create_server_screen.dart` | `name` + `permission` on user insert; should call `seed_org_departments` RPC |
| `lib/screens/home_screen.dart` | Invite insert/update uses `permission`; missing `expires_at`, `role`, `max_uses` |
| `lib/screens/invite_join_screen.dart` | `permission` reads; no invite validation; no redemption; department load UX |
| `lib/models/user_role.dart` | Same as P0 — affects all registration inserts |

### P2 — Alerts broken

| File | Issue |
|------|-------|
| `lib/services/alert_service.dart` | Insert `level`, `sender_user_id`; remove v1 columns; optional `alert_targets` |
| `lib/utils/alert_delivery_tracker.dart` | `created_by` → resolve via `sender_user_id` + current user profile id |
| `lib/utils/alert_utils.dart` | Read `level` (with `type` fallback during migration) |
| `lib/screens/home_screen.dart` | Pass `users.id` as sender, not auth uuid |
| `lib/screens/leader_home_screen.dart` | Read `level`; resolve sender for self-skip |
| `lib/screens/member_home_screen.dart` | Read `level` in handler + history list |
| `lib/screens/alert_screen.dart` | Display `level` not `type` |

### P3 — Organization management broken

| File | Issue |
|------|-------|
| `lib/services/user_org_service.dart` | `updateRole()` via `toDbFields()` |
| `lib/screens/admin_user_detail_screen.dart` | Indirect — role save fails until `toDbFields` fixed; add member dept validation |
| `lib/screens/home_screen.dart` | Invite regenerate filter on `permission` |

### P4 — Nice-to-have cleanup

| File | Issue |
|------|-------|
| `lib/services/department_service.dart` | Replace `seedDefaults()` with `rpc('seed_org_departments')`; drop extra "Evacuation" |
| `lib/services/group_service.dart` | Pass `added_by` on member insert |
| `lib/models/alert_targeting.dart` | Align client targets with v2 `target_type` enum when enabling server targeting |
| `lib/models/alert_constants.dart` | `AlertTarget.medic`/`driver` → department-based targets |
| `lib/screens/leader_home_screen.dart` | Persist targets to `alert_targets`; server-side targeting |
| `lib/screens/member_home_screen.dart` | `alert_receipts`; remove local-only test button fields |
| `lib/screens/home_screen.dart` | Invite expiry/revoke UI; `created_by` on invites |
| **New files needed** | `invite_service.dart`, `alert_receipt_service.dart`, optional `audit_service.dart` |
| `test/widget_test.dart` | Points at old Supabase project URL — update to match v2 or mock |

### Compatible (no schema changes required)

`lib/navigation/role_navigation.dart`, `lib/screens/start_screen.dart`, `lib/screens/join_server_screen.dart`, `lib/widgets/org_user_widgets.dart`, `lib/screens/groups_screen.dart`, `lib/screens/departments_screen.dart`, `lib/screens/leader_org_screen.dart` (after P0), `lib/screens/profile_screen.dart` (after P0), `lib/screens/users_screen.dart` (after P0)

---

## Required fixes grouped by priority

### P0 — App will not run (~2–3 hours)

1. Remove `permission` from all SELECT strings (`main.dart`, `login_screen.dart`, `user_org_service.dart`).
2. Change `UserRole.toDbFields()` to return `{role: normalized}` only.
3. Remove `permission` fallback from `resolveRaw()` or keep read-only fallback for one release (not needed on fresh v2 DB).
4. Smoke test: cold start with session, login, profile load, users list.

### P1 — Registration broken (~4–6 hours)

1. **`create_server_screen.dart`:** Remove `name`; insert `{callsign, role, department_id, status}`; call `supabase.rpc('seed_org_departments', params: {'p_org_id': orgId})`.
2. **`home_screen.dart`:** Invite insert `{role, expires_at, max_uses, created_by?}`; read `role`; regenerate filter `.eq('role', …)`.
3. **`invite_join_screen.dart`:** Read `role`; validate expiry/revoked/usage; insert `invite_redemptions`; increment `use_count` (or RPC `redeem_invite` later); load departments on code change/blur.
4. Default `expires_at` policy (e.g. +30 days) and `max_uses` (e.g. 100 for member, 10 for leader).

### P2 — Alerts broken (~3–5 hours)

1. **`alert_service.dart`:** Insert `{level, message, sender_user_id, is_test}`; resolve `users.id` from auth before insert.
2. Insert default `alert_targets` row `{target_type: 'organization'}` (recommended even before Edge Function).
3. Replace all `alert['type']` reads with `alert['level']` (keep temporary fallback).
4. **`alert_delivery_tracker.dart`:** Compare `sender_user_id` to current profile `users.id`.
5. Test: admin RED alert → member fullscreen; leader send → no self-alarm; GREEN → snackbar.

### P3 — Organization management broken (~1–2 hours)

1. Fix `updateRole` (inherits from P0 `toDbFields`).
2. Validate member must have `department_id` in admin UI before save.
3. Fix invite regenerate (inherits from P1).

### P4 — Nice-to-have cleanup (~1–2 days)

1. `alert_receipts` service + member ack button + leader ack dashboard.
2. Server alert history replacing SharedPreferences.
3. `alert_templates` picker for leaders/admins.
4. `audit_log` on admin actions.
5. `device_tokens` + FCM (separate phase).
6. `InviteService` extraction; invite revoke/expiry UI.
7. Update widget test Supabase URL or mock auth.
8. Typed Dart models for core entities.

---

## v2 tables not referenced by Flutter

| Table | Purpose | Priority to wire |
|-------|---------|------------------|
| `invite_redemptions` | Invite audit | P1 |
| `alert_targets` | Targeting | P2 (default org row) / P4 (full) |
| `alert_target_users` | Explicit users | P4 |
| `alert_receipts` | Ack / delivery | P4 |
| `alert_templates` | Presets | P4 |
| `audit_log` | Compliance | P4 |
| `device_tokens` | FCM | Future phase |
| `user_statuses` | Reference | Read-only catalog (Flutter hardcodes matching values ✓) |
| `department_templates` | Seed source | Used via RPC only |

---

## Estimated effort to complete Flutter v2 migration

| Phase | Scope | Effort |
|-------|-------|--------|
| **P0** | Login, session, profile, user list queries | **2–3 hours** |
| **P1** | Org create, invites, invite join, department seed RPC | **4–6 hours** |
| **P2** | Alert insert, level field, sender_user_id, self-delivery | **3–5 hours** |
| **P3** | Role update, invite regenerate, admin validation | **1–2 hours** |
| **P4** | Receipts, targeting, audit, templates, tests, cleanup | **1–2 days** |

### Total to production-usable (P0–P2)

**~10–14 hours** (1.5–2 working days) for a functioning app: register org, invite users, login, send/receive RED and GREEN alerts org-wide.

### Total to full v2 feature parity (P0–P4)

**~3–4 working days** including acknowledgements, invite lifecycle UX, and server-side targeting groundwork.

---

## Recommended implementation order

```
P0 (unblock auth)
  → P1 (unblock registration)
    → P2 (unblock alerts)
      → P3 (admin polish)
        → P4 (receipts, targeting, audit)
```

**Do not enable `AlertTargeting.serverSideEnabled`** until `alert_targets` inserts and recipient filtering (Edge Function or client-side receipt check) are implemented.

---

## Go / no-go (Flutter on v2 DB)

| Milestone | Status |
|-----------|--------|
| App launches to StartScreen | ✓ (no DB on start) |
| Existing user session restore | **No-go** until P0 |
| New org registration | **No-go** until P0 + P1 |
| Invite join | **No-go** until P0 + P1 |
| Send / receive alerts | **No-go** until P0 + P2 |
| Groups / departments / status | **No-go** until P0 (profile queries) |

**Verdict:** Flutter is **not compatible** with the deployed v2 database. Minimum viable migration is **P0 + P1 + P2** before any production user testing.
