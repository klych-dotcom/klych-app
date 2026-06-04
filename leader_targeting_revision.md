# KLYCH v2 — Leader Targeting UX Revision

**Date:** 2026-05-31  
**Scope:** Flutter Leader UI only — no Supabase schema changes, no migrations, no Edge Functions.

---

## Summary

Revised organization targeting from single-select “Ціль” to multi-select “Отримувачі” with union semantics. Group creation moved from Groups screen to Users bulk actions. Groups screen is now view-only.

---

## 1. Rename target section → Отримувачі

| Before | After |
|--------|-------|
| 🎯 Ціль / ЦІЛЬ | **Отримувачі** |

**Files:** `leader_org_screen.dart`, `leader_home_screen.dart`

---

## 2. Multi-selection on Organization screen

**Before:** Single `AlertTargetSpec` — one status OR one department OR one group OR one user.

**After:** `AlertRecipientsSelection` with accumulating sets:

- `statusCodes`
- `departmentIds`
- `groupIds`
- `userIds`

User may combine any criteria (e.g. Medics + Logistics, On Duty + Group A).

**UI:**

- Filter chips toggle selection (multi-select)
- Bottom bar: `Отримувачі: N` + criteria summary
- “СКИНУТИ” clears all selections

**Recipient count:** Union of all matching users (disabled users excluded).

**New model:** `lib/models/alert_recipients_selection.dart`

**Widget updates:** `org_user_widgets.dart` — `OrgStatusSummary`, `DepartmentFilterChips` accept `Set` + toggle callbacks.

---

## 3. Alert creation from multiple selections

**Flow:**

```
LeaderOrgScreen (multi-select)
  → LeaderHomeScreen(initialRecipients: ...)
  → AlertService.createAlert(recipients: ...)
  → N alert_targets rows (+ alert_target_users for users)
```

**`AlertService.createAlert` signature:**

```dart
createAlert({
  required AlertRecipientsSelection recipients,
  ...
})
```

**Target row mapping (`toTargetSpecs()`):**

| Selection | `alert_targets` rows |
|-----------|---------------------|
| Empty | 1× `organization` |
| Each status | 1× `status` per code |
| Each department | 1× `department` per id |
| Each group | 1× `group` per id |
| Any users | 1× `users` + rows in `alert_target_users` |

**History label:** Joined with ` + ` (e.g. `Медики + Логістика + ALPHA`).

---

## 4. Groups screen → view only

**Before:** Create, rename, archive, manage members on Groups screen.

**After:** `GroupsScreen` displays only:

- Group name
- Member count
- Member list (callsign + status)

Title: **ПЕРЕГЛЯД ГРУП**. No FAB, no edit/archive actions.

---

## 5. Users screen bulk actions (Leader)

When `adminMode: false` and user is Leader:

- Checkbox multi-select on user list
- Bottom bar when selection non-empty:
  - **Створити групу** — name dialog → `GroupService.createGroupWithMembers`
  - **Оповістити обраних** — `LeaderHomeScreen` with user-only `AlertRecipientsSelection`

---

## 6. Group creation bug fix

**Root cause:** `GroupsScreen._createGroup()` had no error handling; failures closed the dialog silently.

**Fix:** Group creation removed from Groups screen. Users screen uses `createGroupWithMembers()` with try/catch + SnackBar feedback. On success, selection clears and group appears on next Groups refresh.

---

## 7. Department localization (UI only)

**New:** `lib/utils/department_labels.dart`

| DB value | UI label |
|----------|----------|
| Headquarters | Штаб |
| Medics | Медики |
| Drivers | Водії |
| Logistics | Логістика |
| Communications | Зв'язок |

Applied in: org filters, user tiles, departments list, admin user detail, invite join dropdown. DB values unchanged.

---

## Files changed

| File | Change |
|------|--------|
| `lib/models/alert_recipients_selection.dart` | **NEW** — multi-select model |
| `lib/models/alert_target_spec.dart` | Added `forUsers()` |
| `lib/services/alert_service.dart` | `recipients` param, multi-row insert |
| `lib/services/group_service.dart` | `createGroupWithMembers()` |
| `lib/services/user_org_service.dart` | Localized department name |
| `lib/utils/department_labels.dart` | **NEW** |
| `lib/widgets/org_user_widgets.dart` | Multi-select chips, selection highlight |
| `lib/screens/leader_org_screen.dart` | Multi-select + Отримувачі |
| `lib/screens/leader_home_screen.dart` | Recipients display + new API |
| `lib/screens/groups_screen.dart` | View-only |
| `lib/screens/users_screen.dart` | Bulk select + group/alert actions |
| `lib/screens/home_screen.dart` | Admin test alert API |
| `lib/screens/departments_screen.dart` | Localized names |
| `lib/screens/admin_user_detail_screen.dart` | Localized dropdown |
| `lib/screens/invite_join_screen.dart` | Localized dropdown |

---

## Verification

```bash
flutter analyze lib/
flutter test
```

**Manual checks:**

1. Organization: select Medics + Logistics → count updates, both chips selected
2. Create alert → multiple `alert_targets` rows in Supabase
3. Users: select 3 users → Create Group → group + members in DB, visible in Groups
4. Users: select users → Оповістити обраних → Leader Home pre-filled
5. Department chips show Ukrainian labels; DB still English

---

## Out of scope

- Schema / RLS changes
- Edge Functions
- Push notification delivery logic
