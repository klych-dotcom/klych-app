# KLYCH Flutter v2 Migration Report — Phase 2

**Date:** 2026-05-31  
**Scope:** P0 + P1 + P2 implementation (per `flutter_v2_audit.md`)  
**Database:** Supabase v2 (unchanged — no SQL modifications)

---

## 1. Files modified

| File | Changes |
|------|---------|
| `lib/models/user_role.dart` | Removed `permission` fallback; `toDbFields()` writes `role` only |
| `lib/main.dart` | Session restore selects `role` only |
| `lib/screens/login_screen.dart` | Login selects `role` only |
| `lib/services/user_org_service.dart` | Removed `permission` from select; added `currentUserId()` |
| `lib/screens/create_server_screen.dart` | RPC `seed_org_departments`; v2 user insert |
| `lib/screens/home_screen.dart` | v2 invites (`role`, `expires_at`, `max_uses`, `created_by`); v2 alert send |
| `lib/screens/invite_join_screen.dart` | Invite validation, redemption, `use_count` increment; auto-load departments |
| `lib/services/alert_service.dart` | v2 alert insert + default `alert_targets` row |
| `lib/utils/alert_delivery_tracker.dart` | Self-delivery via `sender_user_id` |
| `lib/utils/alert_utils.dart` | `resolveLevel()` / `levelLabelFromAlert()` for v2 `level` field |
| `lib/screens/leader_home_screen.dart` | v2 alert send/receive; self-delivery fix |
| `lib/screens/member_home_screen.dart` | v2 alert receive; self-delivery fix; history reads `level` |
| `lib/screens/alert_screen.dart` | Displays `level` not `type` |

**Not modified (per instructions):** `lib/main.dart` credentials, `supabase/v2/*.sql`

---

## 2. P0 completed

- [x] Removed all `users.permission` SELECT usage (`main.dart`, `login_screen.dart`, `user_org_service.dart`)
- [x] `UserRole.toDbFields()` returns `{role: normalized}` only
- [x] `UserRole.resolveRaw()` uses `role` only (legacy medic/driver still map to member via `authorizationRole`)
- [x] All role resolution paths use `role` column

---

## 3. P1 completed

### Organization creation (`create_server_screen.dart`)

- [x] Replaced `DepartmentService.seedDefaults()` with `supabase.rpc('seed_org_departments', params: {'p_org_id': orgId})`
- [x] Removed `users.name` and `users.permission` from insert
- [x] Admin user inserted with v2 fields: `auth_id`, `callsign`, `role`, `organization_id`, `department_id` (Headquarters), `status`

### Invites (`home_screen.dart`)

- [x] Create invites with `role`, `expires_at` (+30 days), `max_uses` (100 member / 10 leader), `created_by`
- [x] Read `role` instead of `permission`
- [x] Regenerate filters by `role`; updates active invite or creates new one
- [x] Only surfaces active invites (`revoked_at` null, not expired, under use limit)

### Invite redemption (`invite_join_screen.dart`)

- [x] Validates `revoked_at IS NULL`, `expires_at > now()`, `use_count < max_uses`
- [x] Reads `invites.role` for role assignment
- [x] Inserts `invite_redemptions` row after user creation
- [x] Increments `invites.use_count`
- [x] Departments load on invite code change (listener) — no keyboard Done required

---

## 4. P2 completed

### Alert service (`alert_service.dart`)

- [x] Insert uses `level`, `sender_user_id`, `is_test` (removed `type`, `created_by`, `created_by_name`)
- [x] Callers pass `users.id` as `senderUserId` (via `UserOrgService.currentUserId()` or cached profile id)
- [x] Inserts default `alert_targets` row with `target_type = 'organization'`

### Alert readers

- [x] `alert_utils.dart` — `resolveLevel()` reads `level` with `type` fallback for old local cache
- [x] `leader_home_screen.dart` — RED/GREEN detection and history use `level`
- [x] `member_home_screen.dart` — same
- [x] `alert_screen.dart` — displays level label

### Self-delivery prevention

- [x] `alert_delivery_tracker.dart` — `isOwnAlert()` compares `sender_user_id` to current `users.id`
- [x] Leader and member screens pass `currentUserId` (not auth uuid)

### Admin test alert

- [x] `home_screen.dart` test alert sets `is_test: true`

---

## 5. Remaining P3 / P4 work (not implemented)

### P3 — Organization management polish

- Admin UI: validate member must have `department_id` before save
- Invite UX: show expiry date, usage count, revoke button (`revoked_at`)
- `audit_log` writes on admin actions

### P4 — Feature completion

- `alert_receipts` — delivery, open, acknowledge tracking
- Server-side alert history (replace SharedPreferences-only cache)
- Full `alert_targets` targeting (department, group, status, explicit users)
- Enable `AlertTargeting.serverSideEnabled` + Edge Function recipient resolution
- `alert_templates` picker
- `device_tokens` + FCM push
- `InviteService` extraction
- `group_members.added_by` on insert
- Update `test/widget_test.dart` Supabase URL to v2 project (still uses old test URL)
- Typed Dart models for core entities

---

## 6. Manual testing checklist

### Registration & auth

- [ ] **Create org** — Start → Create Server → fill fields → lands on admin HomeScreen
- [ ] **Departments seeded** — Admin → Підрозділи → 5 departments (Headquarters, Medics, Drivers, Logistics, Communications)
- [ ] **Invites visible** — Admin home shows member + leader 6-digit codes
- [ ] **Member invite join** — Join → invite code → callsign + password → select department → MemberHomeScreen
- [ ] **Leader invite join** — Leader code → no department required → LeaderHomeScreen
- [ ] **Expired invite rejected** — Manually set `expires_at` in past → join shows error
- [ ] **Revoked invite rejected** — Set `revoked_at` → join shows error
- [ ] **Exhausted invite rejected** — Set `use_count >= max_uses` → join shows error
- [ ] **Login** — Admin email/password → correct home screen
- [ ] **Session restore** — Kill app, reopen → returns to role home (not StartScreen)

### Alerts

- [ ] **Admin RED test** — Admin → Тест тривоги → alert row in DB (`alerts.level = RED`, `is_test = true`)
- [ ] **Leader RED alert** — Leader sends RED → member receives fullscreen alarm + vibration
- [ ] **Leader GREEN alert** — Leader sends GREEN → member sees green snackbar (no fullscreen)
- [ ] **Leader self-delivery** — Leader sends alert → leader does NOT get own alarm
- [ ] **Admin self-delivery** — Admin test alert → admin gets local dialog only (no duplicate via realtime self-fire)
- [ ] **Member realtime** — Member connected indicator green; receives alerts from other users
- [ ] **DB alert_targets** — Each new alert has one `alert_targets` row with `target_type = organization`
- [ ] **DB invite_redemptions** — After join, redemption row exists and `use_count` incremented

### Org management (should work post-P0)

- [ ] **Users list** — Admin → Користувачі → all org users load
- [ ] **Profile status** — Member → profile → change status → saves
- [ ] **Leader org dashboard** — Realtime status updates when member changes status
- [ ] **Groups** — Create group, add/remove members

---

## Verification commands

```bash
flutter analyze   # 0 warnings (info-level deprecations only)
flutter test      # smoke test passes
```

---

## Summary

Flutter is now aligned with Supabase v2 for **core flows**: org bootstrap, invites, login, session restore, and org-wide RED/GREEN alerts with self-delivery prevention. P3/P4 items (receipts, full targeting, audit, FCM) remain for future phases.
