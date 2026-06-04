# Phase 4 — Leader Workflow, Targeting Logic, Performance & Design Unification

## Summary

Phase 4 fixes critical leader targeting (intersection → UNION), establishes `RecipientResolver` as the single source of truth, repairs group member counts, improves leader UX/performance, and extends the KLYCH design system.

No schema changes.

---

## 1. Targeting Fixes

### Root cause (Section 1)
`AlertRecipientsSelection` used **AND-intersection** across status/department/group filters. Selecting Резерв + Штаб + Керівники with no single user matching all three produced **Recipients = 0**, while `toTargetSpecs()` could still fall back incorrectly.

### Fix: UNION semantics
Recipients = **StatusMatches ∪ DepartmentMatches ∪ GroupMatches ∪ ExplicitUsers**

- Rewrote `_matchesFilters` → per-category OR matching, combined with set union
- `toTargetSpecs()` always emits **separate native rows** per status/department/group (aligned with `AlertDeliveryService` DB union)
- Removed intersection collapse to explicit-only user rows for multi-category selections

### "Вся організація" (Section 6)
- Added `orgWide` flag on `AlertRecipientsSelection` (default **`true`** for emergency default)
- Dedicated chip on leader recipient screen
- Selecting any filter disables org-wide; toggling org-wide resets to org-only mode

---

## 2. Single Source of Truth — `RecipientResolver`

New: `lib/services/recipient_resolver.dart`

Used consistently for:
| Consumer | Usage |
|----------|-------|
| Recipient counter | `resolveRecipients().count` |
| User preview list | `resolvedUsers` / `previewCallsigns()` |
| Send button state | `canSend` |
| `AlertService.createAlert()` | Pre-validation + label count |
| Leader home send | Same resolver with `excludeUserId` |
| Leader org bottom panel | `RecipientPreviewPanel` |

**UI count and delivery IDs cannot diverge** — both call the same resolver.

---

## 3. Group Fixes (Section 3)

### Root cause
`GroupService._memberSelect` omitted `group_id` in batch embed query. Rows could not be grouped by group → **Керівники (0)** despite members existing.

### Fix
```dart
'group_id, user_id, users!group_members_user_id_fkey(...)'
```

Group chips now show `Name (N)` with accurate member counts. Groups list uses same batch fetch.

---

## 4. Leader Recipient Screen UX (Sections 4–5)

- Removed all helper subtitle text
- Section headers only: СТАТУСИ · ПІДРОЗДІЛИ · ГРУПИ · КОРИСТУВАЧІ
- **RecipientPreviewPanel** shows:
  ```
  ОТРИМУВАЧІ (4)
  • BOSS
  • CRUZO
  • ...
  ```
- Removed `pruneUsersToVisible` on filter change (was hiding users under intersection logic)
- User list shows **all searchable users**, not filter-narrowed list (filters affect delivery union, not list visibility)

---

## 5. Search (Section 7)

- `KlychSearchField` component
- **Admin Users screen** — realtime callsign filter
- **Leader recipient screen** — same search over full org user list

---

## 6. History Improvements (Sections 9–10)

- Leader home restructured: **compact compose header**, history uses remaining screen (`Expanded`)
- Optimistic insert on send preserved (instant entry)
- Pull-to-refresh on history feed
- Renamed section: **ІСТОРІЯ ОПОВІЩЕНЬ**

---

## 7. Design System (Sections 11–13)

### New/updated components
| Component | Purpose |
|-----------|---------|
| `KlychBrandMark` | Unified "K" brand tile (replaces orange star) |
| `KlychSearchField` | Consistent search input |
| `RecipientPreviewPanel` | Delivery preview with callsigns |
| Compact `UserOrgListTile` | 6px vertical padding, 4px margin |

### Contrast fixes
- Primary actions use `KlychTheme.alertRed` / `alertGreen` on dark surface (not red-on-red)
- Filter chips: selected text `textPrimary`, borders use alpha blends
- Leader header uses theme tokens throughout

---

## 8. Performance Findings & Fixes (Section 14)

| Issue | Fix |
|-------|-----|
| `_buildTargetLabels` N+1 queries per alert | Batch fetch all targets + target_users; compute counts in memory |
| Leader org full reload on user update | Already patched single-user (Phase 3); retained |
| Group N+1 member fetch | Batch `inFilter('group_id', ...)` with `group_id` in select |
| Intersection recalc + prune on every toggle | Removed prune; union resolver is O(n) per toggle |
| Duplicate recipient APIs | Consolidated to `RecipientResolver` |

No duplicate realtime listeners introduced. Existing dispose patterns retained.

---

## 9. Files Modified

| File | Change |
|------|--------|
| `lib/services/recipient_resolver.dart` | **New** — single source of truth |
| `lib/models/alert_recipients_selection.dart` | UNION logic, orgWide, native toTargetSpecs |
| `lib/services/group_service.dart` | Include `group_id` in member select |
| `lib/services/alert_service.dart` | Uses RecipientResolver |
| `lib/services/alert_delivery_service.dart` | Batch target label building |
| `lib/screens/leader_org_screen.dart` | Full UX rewrite |
| `lib/screens/leader_home_screen.dart` | Compact compose, larger history, brand mark |
| `lib/screens/users_screen.dart` | Search |
| `lib/widgets/klych_components.dart` | Brand, search, preview components |
| `lib/widgets/org_user_widgets.dart` | Ultra-compact cards |
| `test/alert_delivery_service_test.dart` | UNION tests |

---

## 10. Verification

```
flutter analyze → 0 errors (info/warning hints only)
flutter test    → 12/12 passed
```

### Manual regression checklist
- ✓ Status + Department + Group = union of all matching users
- ✓ Recipient count matches preview and delivery
- ✓ Group shows correct member count
- ✓ "Вся організація" targets all active users
- ✓ Leader history appears immediately on send
- ✓ Search filters large user lists
- ✓ Admin/Member flows unchanged
- ✓ Receipts/acknowledgements path unchanged

---

## 11. Remaining Technical Debt

- `KlychSearchField` clear button requires parent `setState` on change (no internal listener)
- Profile, login, group details screens not fully migrated to new brand mark
- Admin home invite cards retain legacy styling
- Flutter 3.33 Radio/Dropdown deprecations in admin user detail (pre-existing)
