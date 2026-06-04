# KLYCH Leader UX Fix Pack

**Date:** 2026-05-31  
**Scope:** Flutter Leader UI — no database schema changes.

---

## Issues fixed

### 1. Recipient card cleanup (Leader Home)

**Before:** Redundant `ОТРИМУВАЧІ` + `Отримувачі: N` with target icon (`Icons.gps_fixed`).

**After:**
- Label: `ОТРИМУВАЧІ`
- Value: `Обрано: N` when criteria selected, else `N отримувачів` (org-wide)
- Icon: `Icons.people_outline`
- Criteria summary on second line when applicable

**File:** `lib/screens/leader_home_screen.dart`

---

### 2–4. User multi-select & compact cards

**Root cause (users disappearing):** Organization screen rendered `_previewUsers` from `filterUsersForPreview()`, which applies union filter logic. Selecting a user made `hasAnySelection` true, so only matching users (selected + status/dept/group matches) remained visible.

**Fix:**
- User list always shows all non-disabled org users
- Selection is visual only (`Set<String>` via `AlertRecipientsSelection.userIds`)
- Highlight selected cards; never remove from list

**Compact cards:** Added `compact: true` to `UserOrgListTile` for selection screens:
- Shows: Callsign, Role, Department, Status
- Hides: Registered, Last activity
- Reduced padding/margins (~2× more users on screen)

**Files:** `leader_org_screen.dart`, `users_screen.dart`, `org_user_widgets.dart`

---

### 5. Group creation bug

**Investigation:**

| Check | Finding |
|-------|---------|
| `operational_groups` insert | Column `created_by` matches schema ✓ |
| `group_members` insert | Column `added_by` matches schema ✓ |
| `organization_id` | Passed from current user profile ✓ |
| Refresh after create | Groups screen loads on open; no post-create refresh |
| RLS | Not defined in v2 schema.sql (deployment-dependent) |
| **fetchGroups embed** | **Likely root cause** |

**Root cause:** `group_members` has two FKs to `users` (`user_id`, `added_by`). PostgREST embed `.select('user_id, users(...)')` is ambiguous and can fail, causing `fetchGroups()` to throw → empty groups list even when rows exist in DB.

**Fix:**
- Explicit FK hint: `users!group_members_user_id_fkey(id, callsign, status)`
- Per-group error fallback to `user_id`-only fetch
- Batch insert all members in one request
- `debugPrint` logging on create/fetch
- `DbErrorMessages` for user-facing errors
- SnackBar action to open Groups after create

**Files:** `lib/services/group_service.dart`, `lib/screens/users_screen.dart`

---

### 6. Groups screen — tap to expand

**Before:** All members always visible inline.

**After:**
- Collapsed row: Group name + member count
- Tap toggles member list expansion
- Chevron indicates state

**File:** `lib/screens/groups_screen.dart`

---

## Verification

```bash
flutter analyze lib/
flutter test
```

**Manual:**
1. Leader Home → recipient card shows `ОТРИМУВАЧІ` / `Обрано: N` or `N отримувачів`, people icon
2. Organization → select multiple users; all users stay visible; selected highlighted
3. Users (Leader) → compact cards; multi-select works
4. Create Group → appears immediately in Groups; survives app restart
5. Groups → tap row expands/collapses members
