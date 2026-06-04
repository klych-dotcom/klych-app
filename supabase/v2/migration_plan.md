# KLYCH v2 — Flutter Migration Plan

This document maps the **current Flutter codebase** to the **v2 clean schema** and lists required app changes. Database is rebuilt from zero; backward compatibility with v1 is not a goal.

---

## Execution order (database)

1. Drop old public schema (or create new Supabase project)
2. Run `supabase/v2/schema.sql`
3. Run `supabase/v2/seed.sql`
4. Run `supabase/v2/verification.sql`
5. Point Flutter `main.dart` at new Supabase project URL/keys

---

## Current Flutter query inventory vs v2 schema

| Current table/column | v2 equivalent | Action |
|---------------------|---------------|--------|
| `organizations` | `organizations` | Compatible |
| `users.role` + `users.permission` | `users.role` only | **Remove `permission` writes/reads** |
| `users.department_id` | `users.department_id` | Compatible |
| `users.status` | `users.status` → FK `user_statuses` | Compatible values |
| `users.is_disabled` | `users.is_disabled` | Compatible |
| `users.last_activity_at` | `users.last_activity_at` | Compatible |
| `departments` | `departments` | Compatible |
| `invites.permission` | `invites.role` | **Rename column in queries** |
| `invites` (no expiry) | `invites.expires_at`, `max_uses`, `revoked_at` | **Add fields on create/read** |
| `alerts.type` | `alerts.level` | **Rename in AlertService** |
| `alerts.created_by` (auth id) | `alerts.sender_user_id` (users.id) | **Resolve user id before insert** |
| `alerts.created_by_name` | Dropped (join `users.callsign`) | **Remove; use join/display** |
| Client-side targeting | `alert_targets`, `alert_target_users` | **Implement when server targeting enabled** |
| Local alert history only | `alert_receipts` + server history | **New ack flow** |
| `DepartmentService.seedDefaults()` | `SELECT seed_org_departments(org_id)` | **Call RPC or replicate templates** |
| Realtime `alerts` INSERT | Same + `alert_receipts` UPDATE | **Extend subscriptions** |

---

## What remains compatible (minimal changes)

| Feature | Files | Change level |
|---------|-------|--------------|
| Auth routing admin/leader/member | `main.dart`, `login_screen.dart`, `role_navigation.dart` | Low — read `role` only |
| Admin home / test alert | `home_screen.dart` | Medium — alert insert shape |
| Leader home / send alert | `leader_home_screen.dart` | Medium — sender_user_id + targets |
| Member realtime alerts | `member_home_screen.dart` | Medium — receipts + ack |
| Department admin UI | `departments_screen.dart` | Low |
| Group management UI | `groups_screen.dart` | Low |
| User list UI | `users_screen.dart`, widgets | Low — drop `permission` |
| Profile / status | `profile_screen.dart` | Low |
| Leader org dashboard | `leader_org_screen.dart` | Low |
| Self-delivery prevention | `alert_delivery_tracker.dart` | Medium — use `sender_user_id` |
| Navigation / screens structure | All | **No change required** |

---

## Required Flutter updates (by priority)

### P0 — Registration & org bootstrap

| File | Change |
|------|--------|
| `create_server_screen.dart` | After org insert: `await supabase.rpc('seed_org_departments', params: {'p_org_id': orgId})`; insert admin without `permission`; set `department_id` to HQ |
| `invite_join_screen.dart` | Read `invites.role` not `permission`; validate `expires_at`, `revoked_at`, `use_count < max_uses`; insert `invite_redemptions`; load departments |
| `home_screen.dart` | Create invites with `role`, `expires_at`, `max_uses`; support revoke (`revoked_at`) |
| `user_role.dart` | Remove `permission` dual-write; `toDbFields()` → `{role}` only |
| `user_org_service.dart` | Remove `permission` from select; update embed query |

### P1 — Alerts

| File | Change |
|------|--------|
| `alert_service.dart` | Insert `level`, `sender_user_id`, `is_test`; create `alert_targets` row; optional `alert_target_users` |
| `alert_constants.dart` | Align with DB check `RED`/`GREEN` |
| `alert_targeting.dart` | Set `serverSideEnabled = true` when Edge Function ready |
| `leader_home_screen.dart` | Persist targets; remove “coming soon” when wired |
| `member_home_screen.dart` | Insert/update `alert_receipts` on open/ack |

### P2 — Acknowledgements & history

| New service | `alert_receipt_service.dart` — CRUD receipts |
| `leader_org_screen.dart` or new screen | Ack dashboard for leaders |
| `home_screen.dart` | Admin alert history + ack stats |

### P3 — Audit

| New service | `audit_service.dart` — insert on admin actions |
| Admin screens | Log role change, user removal, invite create |

### P4 — Invites UX

| Admin UI | Show expiry, usage count, revoke button |
| Registration | Block expired/revoked/over-limit codes with clear errors |

---

## Screens needing updates

| Screen | Updates |
|--------|---------|
| `InviteJoinScreen` | `role` column, invite validation, redemption row |
| `CreateServerScreen` | RPC seed departments |
| `HomeScreen` | Invite v2 fields, alert sender_user_id, history |
| `LeaderHomeScreen` | Target persistence, ack view link |
| `MemberHomeScreen` | Ack button, receipt tracking, server history |
| `AdminUserDetailScreen` | Write `audit_log` on changes |
| `UsersScreen` | Display role only |
| `ProfileScreen` | Status FK validation (already matches seed) |
| `GroupsScreen` | Optional `added_by` on member insert |
| **New (future)** | `AlertHistoryScreen`, `AcknowledgementDashboardScreen` |

**No navigation restructure required** for v2 DB cutover.

---

## Deprecations

| Deprecated | Replacement |
|------------|-------------|
| `users.permission` | `users.role` |
| `invites.permission` | `invites.role` |
| `alerts.type` | `alerts.level` |
| `alerts.created_by` + `created_by_name` | `alerts.sender_user_id` + join |
| `alerts.target` column (v1 optional) | `alert_targets` table |
| Role values `medic`, `driver` | `role=member` + department Medics/Drivers |
| `UserRole.toDbFields()` dual write | Single `role` field |
| Client-only alert history (`SharedPreferences`) | `alert_receipts` + optional local cache |
| `supabase/001_production_sync.sql` | Replaced by `v2/schema.sql` |
| `supabase/org_management_migration.sql` | Replaced by `v2/schema.sql` |

---

## Services refactor map

| Current service | v2 responsibility |
|-----------------|---------------------|
| `DepartmentService` | Unchanged; add `seedFromTemplates(orgId)` via RPC |
| `UserOrgService` | Remove permission; add audit hooks |
| `GroupService` | Add `added_by` on insert |
| `AlertService` | Full alert + targets + receipt fan-out stub |
| **New** `InviteService` | Validate + redeem + increment use_count |
| **New** `AlertReceiptService` | delivered/opened/acknowledged |
| **New** `AuditService` | Append-only audit_log |

---

## Realtime subscription changes

| Channel | Current | v2 |
|---------|---------|-----|
| Member alerts | `alerts` INSERT by org | Same + filter recipients via receipts (future) |
| Leader alerts | Same | Same |
| Org users | `users` UPDATE by org | Same |
| **New** | — | `alert_receipts` UPDATE for ack dashboard |

---

## FCM preparation (schema only)

`device_tokens` table exists. Flutter changes deferred until FCM phase:

- Register token on login
- Upsert into `device_tokens`
- Edge Function sends push on alert insert (future)

---

## RLS & Edge Functions (future phases)

**Do not enable RLS** until policies exist — schema documents org-scoped tables.

Recommended policy shape (future):

- All rows: `organization_id = current_user_org()`
- Leader: write own `operational_groups`, send alerts
- Admin: full org management
- Member: read own receipts, update own status/ack

Edge Functions (future):

- `redeem_invite` — atomic invite validation + user create
- `dispatch_alert` — resolve targets → insert `alert_receipts`
- `send_push` — FCM fan-out

---

## Testing checklist after Flutter cutover

- [ ] Create org → 5 departments from templates
- [ ] Admin login → home loads
- [ ] Create member + leader invites with expiry
- [ ] Member register → department required → success
- [ ] Leader register → role locked, no self-select
- [ ] Expired/revoked invite rejected
- [ ] RED alert → member fullscreen + receipt row
- [ ] Member acknowledges → leader sees ack
- [ ] Leader targets department (when P1 done)
- [ ] Status change visible on leader dashboard (realtime)
- [ ] Admin changes role → audit_log row

---

## Summary

The v2 schema is **cleaner and strictly org-scoped**, with proper invite lifecycle, alert targeting tables, and acknowledgement tracking. Current Flutter implements roughly **60%** of the v2 data model (org, departments, groups, basic alerts). **P0 changes** (role rename, invite v2, department seed RPC) are required before the app works on a fresh v2 database. Alert targeting and acknowledgements are **schema-ready** but need Flutter + Edge Function work in subsequent milestones.
