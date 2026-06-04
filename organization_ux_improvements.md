# KLYCH — Organization UX Improvements

**Date:** 2026-05-31  
**Scope:** Flutter-only UX and organization workflow (no schema changes)

---

## Summary

Seven UX improvements implemented against the existing Supabase v2 schema: member status on home screen, Ukrainian status labels, leader org filtering, alert target selection with `alert_targets` persistence, leader group management access, profile simplification, and leader home cleanup.

---

## 1. Member status UX redesign

### Screens modified
- `lib/screens/member_home_screen.dart`
- `lib/screens/profile_screen.dart`

### Widgets added
- `lib/widgets/member_status_selector.dart` — dropdown with Ukrainian labels; writes DB codes unchanged

### Behavior
- Operational status selector on Member Home (always visible)
- Changes call `UserOrgService.updateStatus()` immediately
- Profile screen: callsign edit + read-only account info (email, role, department, current status display)

### Services
- `UserOrgService.updateCallsign()` added

---

## 2. Leader Home cleanup

### Screens modified
- `lib/screens/leader_home_screen.dart`

### Changes
- Removed “Server-side targeting not yet enabled” banner
- Removed legacy medic/driver target dropdown and org-wide fallback warning
- Target shown as read-only chip with **ЗМІНИТИ** → opens org screen in target-pick mode

---

## 3. Organization screen — status filtering

### Screens modified
- `lib/screens/leader_org_screen.dart`
- `lib/widgets/org_user_widgets.dart`

### Widgets updated
- `OrgStatusSummary` — `FilterChip` per status; tap toggles filter; selected chip highlighted

### Behavior
- Tap **Резерв: 3** → user list shows only `available` users
- Tap again → clears status filter
- Status filter also updates alert target to status-based targeting

---

## 4. Department filtering

### Widgets added
- `DepartmentFilterChips` in `org_user_widgets.dart`

### Behavior
- Department names are tappable chips
- Tap **Medics** → filters user list to that department
- Tap again → clears department filter
- Department filter updates alert target to department targeting

---

## 5. Alert recipient selection & targeting flow

### Models added
- `lib/models/alert_target_spec.dart`

### Services modified
- `lib/services/alert_service.dart` — accepts `AlertTargetSpec`, writes:
  - `alert_targets` row (`organization` | `department` | `group` | `status` | `users`)
  - `alert_target_users` rows when target type is `users`

### Targeting flow design

```
LeaderOrgScreen
  ├─ Filter by status chip / department chip / view users
  ├─ Select group chip → group target
  ├─ Tap user row → user target
  └─ [СТВОРИТИ ОПОВІЩЕННЯ]
         │
         ▼
LeaderHomeScreen(initialTarget: AlertTargetSpec)
  ├─ Shows preselected target label
  ├─ Compose message + level
  └─ Send → AlertService.createAlert() → alert_targets + optional alert_target_users
```

### Supported targets (v2 schema)

| UI selection | `target_type` | Extra columns |
|--------------|---------------|---------------|
| Default / reset | `organization` | — |
| Department chip | `department` | `department_id` |
| Status chip | `status` | `status_code` |
| Group chip | `group` | `group_id` |
| User tap | `users` | `alert_target_users` |

**Note:** Realtime delivery remains org-wide (no Edge Function). Target rows are persisted for future server-side resolution.

### Navigation changes
- `LeaderHomeScreen({AlertTargetSpec? initialTarget})`
- `LeaderOrgScreen({bool selectTargetMode})` — returns target when opened from Leader Home **ЗМІНИТИ**

---

## 6. Leader-managed groups

### Screens modified
- `lib/screens/users_screen.dart` — Groups icon in app bar for leaders
- `lib/screens/groups_screen.dart` — archive confirmation, Ukrainian copy, `added_by` on member add
- `lib/screens/leader_org_screen.dart` — Groups shortcut retained

### Group management flow

```
UsersScreen (leader)
  └─ App bar → GroupsScreen
        ├─ Create group
        ├─ Rename group
        ├─ Archive group (delete — no is_archived on operational_groups)
        └─ Manage members (add/remove, records added_by)
```

Leaders also reach groups from Organization screen app bar.

---

## 7. Ukrainian operational terminology

### Files modified
- `lib/models/user_status.dart`

| DB value | UI label |
|----------|----------|
| `available` | Резерв |
| `on_duty` | Чергова зміна |
| `deployed` | На виїзді |
| `vacation` | Відсутній |
| `unavailable` | Недоступний |

Used everywhere via `UserStatus.label()`.

---

## Files modified (complete list)

| File | Change |
|------|--------|
| `lib/models/user_status.dart` | Ukrainian labels |
| `lib/models/alert_target_spec.dart` | **New** |
| `lib/models/alert_targeting.dart` | `serverSideEnabled = true` |
| `lib/services/alert_service.dart` | v2 target rows |
| `lib/services/user_org_service.dart` | `updateCallsign()` |
| `lib/services/group_service.dart` | `added_by` on member insert |
| `lib/widgets/member_status_selector.dart` | **New** |
| `lib/widgets/org_user_widgets.dart` | Filter chips |
| `lib/screens/member_home_screen.dart` | Status selector |
| `lib/screens/profile_screen.dart` | Callsign + account info |
| `lib/screens/leader_home_screen.dart` | Banner removed, target chip |
| `lib/screens/leader_org_screen.dart` | Filters + targeting + create alert |
| `lib/screens/users_screen.dart` | Leader → Groups |
| `lib/screens/groups_screen.dart` | Archive UX, Ukrainian |
| `lib/screens/home_screen.dart` | `AlertTargetSpec.orgWide()` |

---

## Manual testing checklist

### Member status
- [ ] Member Home shows status dropdown with Ukrainian labels
- [ ] Change status → saves immediately, visible on reload
- [ ] Profile: edit callsign, view email/role/dept (no status editor)

### Leader org filters
- [ ] Tap status chip → filters user list
- [ ] Tap department chip → filters user list
- [ ] Скинути фільтр clears filters

### Alert targeting
- [ ] Select department → bottom shows target → Create Alert → Leader Home shows target
- [ ] Select user → user target persisted in `alert_targets` / `alert_target_users`
- [ ] Select group → `alert_targets.group_id` set on send
- [ ] Send alert → row exists in `alert_targets` table

### Groups (leader)
- [ ] Users screen → Groups icon (leader only)
- [ ] Create / rename / archive group
- [ ] Add/remove members

### Leader home
- [ ] No targeting disabled banner
- [ ] Target label visible; ЗМІНИТИ works

---

## Verification

```bash
flutter analyze lib/
flutter test
```
