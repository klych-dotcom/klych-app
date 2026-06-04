# Phase 3 — Targeting Integrity, Alert History & Unified Design System

## Summary

Fixed critical targeting bug (zero-intersection fallback to org-wide), admin delivery gap, history latency, and established a unified KLYCH design system applied across core screens.

No schema changes. All work within v2 architecture.

---

## 1. Bugs Fixed

### P1 — Zero-recipient intersection still delivered to entire org

**Root cause:** `AlertRecipientsSelection.toTargetSpecs()` contained:

```dart
if (ids.isEmpty) return [AlertTargetSpec.orgWide()];
```

When Department + Status intersection yielded 0 users, the system stored an **organization** target instead of blocking — delivering to all members.

**Fix:**
- Empty intersection now returns `[]` (no targets).
- `AlertService.createAlert()` validates delivery IDs **before** inserting alert row.
- Throws `NoRecipientsException` ("Немає отримувачів для обраних фільтрів") — no alert, targets, or receipts created.
- Leader home and org screen block send UI when count = 0.

### P2 — Multi-filter intersection verified

Intersection logic in `_matchesFilters()` confirmed correct (AND across department/status/group, OR within each category). Added unit tests for dept+status overlap and empty intersection.

### P3 — Admin does not receive targeted alerts

**Root cause:** `HomeScreen` (admin) had **no realtime alert subscription**. Admin was never listening for incoming alerts.

**Fix:** Added `AlertRealtimeListener` mixin to admin `HomeScreen`:
- Subscribes to org alert inserts on load.
- Uses `AlertDeliveryService.shouldUserReceiveAlert()` + receipt checks.
- Triggers fullscreen RED alert / green SnackBar like member/leader.

### P4 — Leader history ~30s delay

**Root cause:** History relied solely on async DB reload after send; no optimistic insert.

**Fix:** Optimistic update on successful send — alert appears instantly in list with recipient/ack counts; background `_loadAlertHistory()` confirms from DB. Realtime handler still refreshes on any org insert.

### P5 — Pull-to-refresh

Added `RefreshIndicator` on:
- Leader alert history
- Leader organization screen (existing, updated styling)
- Member alert history
- Admin users list
- Admin departments list

### P6 — History database-backed

| Role | Source |
|------|--------|
| Leader | `AlertDeliveryService.fetchOrgAlertHistory()` |
| Member | `AlertDeliveryService.fetchUserAlertHistory()` via receipts (SharedPreferences removed for alert data; cleared_at filter kept for UI) |
| Admin test | Org-wide via `AlertService`; admin receives via realtime when receipt exists |

---

## 2. Files Modified

| File | Change |
|------|--------|
| `lib/models/alert_recipients_selection.dart` | Remove org-wide fallback on empty intersection |
| `lib/models/alert_exceptions.dart` | **New** — `NoRecipientsException` |
| `lib/services/alert_service.dart` | Pre-send validation; block zero recipients |
| `lib/services/alert_delivery_service.dart` | `fetchUserAlertHistory()` for members |
| `lib/mixins/alert_realtime_listener.dart` | **New** — shared delivery mixin |
| `lib/theme/klych_theme.dart` | **New** — design tokens + ThemeData |
| `lib/widgets/klych_components.dart` | **New** — shared UI components |
| `lib/widgets/org_user_widgets.dart` | Design system colors; compact cards |
| `lib/main.dart` | Apply `KlychTheme.build()` |
| `lib/screens/leader_home_screen.dart` | Zero block, optimistic history, refresh, theme |
| `lib/screens/leader_org_screen.dart` | Zero block on create, theme |
| `lib/screens/member_home_screen.dart` | DB history, refresh, theme tiles |
| `lib/screens/home_screen.dart` | Admin realtime delivery |
| `lib/screens/users_screen.dart` | Pull-to-refresh, theme |
| `lib/screens/departments_screen.dart` | Pull-to-refresh, KlychCard tiles |
| `test/alert_delivery_service_test.dart` | Intersection + empty target tests |

---

## 3. Targeting Verification

| Scenario | UI Count | DB Targets | Delivery |
|----------|----------|------------|----------|
| Dept only | Matching dept users | dept rows | ✓ |
| Status only | Matching status users | status rows | ✓ |
| Dept + Status (no overlap) | 0 | `[]` — blocked | None |
| Dept + Status (overlap) | Intersection | explicit users row | ✓ |
| Group + Status | Intersection | explicit users row | ✓ |
| Manual users | Selected count | users target | ✓ |
| Zero recipients | 0 | Blocked | None |

---

## 4. History Refresh Verification

1. **Send:** Optimistic insert → instant leader list update.
2. **Background:** `_loadAlertHistory()` merges DB state (ack counts, labels).
3. **Realtime:** Any org alert insert triggers history reload.
4. **Pull:** Manual refresh re-fetches from DB.

---

## 5. Admin Delivery Verification

- Admin subscribes via `admin-alerts-{orgId}` channel.
- Targeted admin receives receipt at creation.
- `shouldUserReceiveAlert()` returns true when receipt exists.
- Fullscreen RED alert opens via shared `AlertRealtimeListener.triggerRedAlert()`.

---

## 6. UI System Created

### Location
- `lib/theme/klych_theme.dart` — tokens
- `lib/widgets/klych_components.dart` — components

### Typography scale
- Display 28 / Title 20·16 / Body 15·13 / Label 11·12 caps

### Spacing scale
- 4 · 8 · 12 · 16 · 20 · 24 · 32

### Color system
- Background `#0C0C0E`, Surface `#161618`, Elevated `#1E1E22`
- Accent `#E85D4C` (operational red)
- Alert RED `#D64545`, GREEN `#4CAF7A`
- Status: available green, on-duty blue, deployed amber, vacation gray, unavailable muted red

### Components
- `KlychCard`, `KlychFilterChip`, `KlychPrimaryButton`
- `KlychAlertHistoryTile`, `KlychSectionHeader`, `KlychEmptyState`
- `KlychConnectionBadge`

### Rules
- Border radius 10–18px; compact list density
- Subtle borders over heavy shadows
- Consistent AppBar via theme (no per-screen color overrides where updated)
- Floating SnackBars; unified dialog/input styles

---

## 7. Design Decisions

- **Operational minimalism:** Dark neutral base, restrained accent — inspired by mission-control / emergency tooling.
- **Information density:** Compact user cards (`UserOrgListTile.compact`) without losing hierarchy.
- **Shared mixin for delivery:** One code path for admin/leader/member notification behavior.
- **Optimistic leader history:** Perceived instant feedback; DB remains source of truth.

---

## 8. Remaining Issues

- Some screens not yet fully migrated (profile, groups details, start/login, alert_screen) — inherit global theme but retain legacy inline styles.
- Admin `HomeScreen` invite cards still use legacy container styling.
- `admin_user_detail_screen` Flutter 3.33 deprecation hints (Radio/Dropdown) — pre-existing.
- Member `cleared_at` still uses SharedPreferences for UI filter only (not alert storage).

---

## Test Results

```
flutter analyze → 0 errors (8 info-level hints, pre-existing/new style lints)
flutter test    → 9/9 passed
```

### Manual verification checklist

1. ✓ Recipient count matches actual delivery
2. ✓ Zero recipients blocks sending with Ukrainian message
3. ✓ Admin receives targeted alerts (realtime + receipt)
4. ✓ Leader history updates immediately (optimistic)
5. ✓ Pull-to-refresh on leader/member/admin lists
6. ✓ Core screens share KlychTheme language
7. ✓ Receipts/acknowledgements unchanged — no regression
