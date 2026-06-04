# KLYCH Leader Targeting & Group Management Fix Pack

**Date:** 2026-05-31  
**Scope:** Flutter Leader UI + client logic — no Supabase schema changes.

---

## Summary

Revised recipient targeting to use **filter intersection** with optional **manual user override**, unified recipient label format `ОТРИМУВАЧІ (N)`, and added full **group management** via Group Details + Users bulk actions.

---

## Files modified

| File | Change |
|------|--------|
| `lib/models/alert_recipients_selection.dart` | Intersection filtering, count logic, alert spec resolution |
| `lib/services/alert_service.dart` | Pass org data to `toTargetSpecs`, unified label |
| `lib/services/group_service.dart` | `fetchGroup`, `addMembers`, explicit delete order, error handling |
| `lib/screens/leader_home_screen.dart` | Single-line `ОТРИМУВАЧІ (N)` card |
| `lib/screens/leader_org_screen.dart` | Filtered user list, live count, prune manual picks |
| `lib/screens/users_screen.dart` | Add to group bulk action, group hub workflow |
| `lib/screens/groups_screen.dart` | Compact list `Name (count)`, tap → details |
| `lib/screens/group_details_screen.dart` | **NEW** — rename, add/remove members, delete |

---

## Logic changes

### Filter intersection (AND across categories, OR within category)

| Category | Rule |
|----------|------|
| Status | User status ∈ selected statuses (if any selected) |
| Department | User department ∈ selected departments (if any) |
| Group | User is member of ≥1 selected group (if any) |
| Combined | All active categories must match |

**Examples:**
- On Duty + Medics → medics currently on duty
- Group + Reserve → reserve members in that group

### Manual user override

| State | Alert recipients |
|-------|------------------|
| Manual users selected | **Only** selected user IDs |
| Filters only, no manual users | All users matching filter intersection |
| No filters, no manual users | Entire organization |

### Recipient count

Same rules as alert delivery — updates live on filter/user changes.

### Alert target rows (`toTargetSpecs`)

| Case | DB rows |
|------|---------|
| Manual users | `users` + `alert_target_users` |
| Single filter category | Native rows (`status` / `department` / `group`) |
| Multiple filter categories | Intersection resolved to `users` + `alert_target_users` |
| No selection | `organization` |

---

## UX changes

### 0. Recipient card
- **Before:** `ОТРИМУВАЧІ` + `Отримувачі: N` (redundant)
- **After:** single line `ОТРИМУВАЧІ (N)` on Leader Home, Organization bottom bar, Users bulk bar
- Removed target icon and duplicate wording
- No use of Ціль / Target in Leader UI

### 1–4. Organization screen
- Status / department / group chips **filter** the user list (intersection)
- All filtered users remain visible; manual selection highlights only
- Manual picks pruned when filters change and user falls out of list
- Count reflects final recipient set

### 8. Compact cards
- `UserOrgListTile(compact: true)` on org + leader users screens
- Shows: callsign, role, department, status
- Hides: registered, last activity

---

## Group management

### Group Details screen (`group_details_screen.dart`)
- Group name + member count
- Member list with status
- **Rename** group
- **Add members** (multi-select from org users)
- **Remove member** (with confirmation)
- **Delete group** (confirmation → removes `group_members` then `operational_groups`)

### Groups list screen
- Format: `Швидке реагування (8)`
- Tap → Group Details
- Refresh after returning from details

### Users screen (Leader hub)
Bulk actions on multi-select:
1. **Створити групу** — new group + members
2. **Додати до групи** — add to existing group
3. **Оповістити** — alert to selected users only

Organization screen is **not** used for group membership management.

---

## Filtering implementation

Core methods on `AlertRecipientsSelection`:

```dart
filterUsersByCriteria(users, groups)  // intersection for list display
estimateRecipientCount(users, groups) // final count
pruneUsersToVisible(visibleUsers)     // drop invalid manual picks
toTargetSpecs(users, groups)          // alert_targets rows
recipientsLabel(count: n)             // "ОТРИМУВАЧІ (n)"
```

Group member lookup uses `group_members.user_id` joined via explicit FK hint `users!group_members_user_id_fkey`.

---

## Verification

```bash
flutter analyze
flutter test
```

**Manual checklist:**
1. Medics filter → only medics in list; count matches
2. On Duty + Medics → intersection only
3. Medics filter, select 2 users → count = 2, alert to those 2 only
4. Medics filter, no manual selection → alert to all medics
5. Leader Home shows `ОТРИМУВАЧІ (N)` single line
6. Create group from Users → visible in Groups → survives restart
7. Group Details: rename, add/remove members, delete works
8. Add selected users to existing group from Users screen

---

## Out of scope

- Database schema / RLS policy changes
- Server-side alert delivery intersection (client stores correct targets)
