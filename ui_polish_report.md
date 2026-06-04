# KLYCH — UI Polish Pass

**Scope:** Visual polish only. No business logic, recipient calculation, alert, realtime, acknowledgement, navigation, Supabase, or schema changes.
**Direction:** Apple-style, clean, minimal, operational. Improve consistency and information density without changing functionality.

**Validation:** `flutter analyze` → 0 errors / 0 warnings (8 pre-existing info hints only, unchanged). `flutter test` → all 12 tests pass.

---

## CHANGED

### 1. Header consistency
- **Online status moved into the identity block.** `KlychAppHeader` (`lib/widgets/klych_components.dart`) now accepts a `connected` flag and renders the online/offline indicator on the same line as the callsign, inside the logo · organization · callsign group. The separate, detached `KlychConnectionBadge` row was removed from Leader Home (`leader_home_screen.dart`) and Member Home (`member_home_screen.dart`); both now read as a single header block.
- **Redundant role labels removed.** The header `subtitle` (which duplicated the role — "ADMIN"/"LEADER"/"MEMBER") was removed from `KlychAppHeader` and from all three home screens (`home_screen.dart`, `leader_home_screen.dart`, `member_home_screen.dart`). Headers now show only organization, callsign, and online status — compact and clean.

### 2. Leader Home screen
- **Message composer ~2× taller.** The alert message `TextField` changed from `maxLines: 1` to `minLines: 2, maxLines: 4` — it now reads as a proper operational composer. Same controller, placement, and behavior.
- **History height reduced & dead space removed.** The fixed `0.42 × screenHeight` history block plus the trailing `Spacer()` (which produced the empty black band at the bottom) were replaced with an `Expanded` history list. Combined with the taller composer, history now occupies roughly the lower third of the screen and the layout fills the full available height with no empty bands. Scrolling and pull-to-refresh preserved.

### 3. Button contrast
- **`KlychPrimaryButton` now auto-selects a high-contrast foreground.** Using `ThemeData.estimateBrightnessForColor`, light fills (e.g. the green INFO button `alertGreen #4CAF7A`, which previously had washed-out ~2.4:1 white text) now use dark text, while red/accent fills keep white text. Label weight raised to w700; disabled state given explicit, still-legible colors; height 48→50. This fixes the low-contrast "red/green on light" readability issue across every screen that uses the component (Leader send, Leader/Admin create-alert & test-alert, Profile, Admin user detail). Alert semantics unchanged — RED stays visually prominent.

### 4. Admin → Users screen density
- **User rows are now the compact tile** (`users_screen.dart` passes `compact: true`). Each row shows callsign, role · department, and the status badge, with ~6px vertical padding instead of the previous tall card that also rendered registration/activity timestamps. Vertical footprint reduced by roughly 55–60%, making 100–500-user lists fast to scan and scroll. Registration/activity details remain available on the user detail screen — no important data lost.

### 5. Design-system consistency (color/typography/components only — no layout changes)
- **Logout dialogs** in Leader Home and Member Home: removed hardcoded `Color(0xFF1C1C1E)`/manual white text/custom shape; they now inherit the unified `dialogTheme` and use `KlychTheme` tokens (`textMuted`, `alertRed`).
- **Profile screen** (`profile_screen.dart`): migrated to `KlychTheme.background`, themed `AppBar`, `labelCaps` section headers, `bodyLarge`/`bodyMedium` text, `KlychPrimaryButton` for save, themed `TextField`, and `KlychEmptyState`.
- **Admin user detail** (`admin_user_detail_screen.dart`): `KlychTheme.background`, themed `AppBar`, `labelCaps` section labels, themed dropdown, `KlychPrimaryButton` for save, `accent`/`alertRed` accents (replacing raw `Colors.red`).
- **Group details** (`group_details_screen.dart`): `KlychTheme.background`, themed `AppBar`, `KlychCard` member rows with consistent radius/spacing/typography, `KlychEmptyState`, themed add/remove actions.
- Spacing, corner radius, typography hierarchy, icon sizing, and section headers on these screens now match the tokens already used by the Leader/Member/Admin home and organization screens.

---

## UNCHANGED (confirmed)

No business logic was touched. Specifically unchanged:
- Recipient calculation / `RecipientResolver` / `AlertRecipientsSelection` (UNION semantics).
- Alert creation, targeting, and delivery.
- Realtime subscriptions and handlers (channels, dedupe, debounced history reload).
- Acknowledgement flow (`AlertReceiptService`, receipts, delivered/acknowledged timestamps).
- Navigation flow (single-`LeaderHomeScreen` guarantees from the stability pass are intact).
- Supabase access and database schema.

All edits were confined to widget styling/layout properties (colors, text styles, paddings, `minLines`/`maxLines`, `Expanded` vs fixed height, component swaps). `flutter test` confirms resolver/delivery tests still pass.

---

## VISUAL CONSISTENCY — screens aligned to the design system

| Screen | Status |
|--------|--------|
| Leader Home | Header block + composer + filled-height history + contrast buttons |
| Member Home | Header block (online status integrated) + themed dialog |
| Admin Home | Header block (role label removed) |
| Admin → Users | High-density compact rows |
| Leader → Organization / Recipients | Already on system (unchanged) |
| Leader Alert Details | Already on system (unchanged) |
| Profile | Migrated to `KlychTheme` |
| Admin User Detail | Migrated to `KlychTheme` |
| Group Details | Migrated to `KlychTheme` |
| Departments / Groups / Users search | Already on system (unchanged) |

Shared components driving consistency: `KlychAppHeader`, `KlychCard`, `KlychSectionHeader`, `KlychPrimaryButton`, `KlychFilterChip`, `KlychSearchField`, `KlychConnectionBadge`, `UserOrgListTile`, `KlychAlertHistoryTile` — all sourced from `KlychTheme` tokens (spacing, radius, typography, color).

---

## FINAL RESULT

KLYCH now presents a unified, Apple-style operational UI:
- A single, compact identity header (logo · organization · callsign · online status) with no duplicated role text.
- A Leader Home that reads as a real message composer and fills the full screen height with no dead black space.
- Accessibility-friendly button contrast on every primary/destructive action while keeping RED alerts visually important.
- High-density Admin user lists suitable for large organizations.
- Consistent spacing, corner radius, typography, iconography, and card styling across Admin, Leader, and Member screens.

No functionality changed; the app is visually consistent and ready for use.
