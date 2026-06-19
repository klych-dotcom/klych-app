# KLYCH — Recipient Selection Fix + UI Polish

Scope: fix the "user selection lost" bug and continue UI polish. No schema,
alerts architecture, targeting logic, realtime, acknowledgements, receipts, or
business logic were changed.

---

## BUG — User selection lost (FIXED)

### Root cause

`AlertRecipientsSelection`'s constructor defaults **`orgWide = true`**:

```6:21:lib/models/alert_recipients_selection.dart
  AlertRecipientsSelection({
    ...
    this.orgWide = true,
  })
```

When the leader manually selected users on **Users → "ОПОВІСТИТИ"**, the selection
was built **without** overriding that default:

```dart
// lib/screens/users_screen.dart (before)
final recipients = AlertRecipientsSelection(
  userIds: Set<String>.from(_selectedUserIds),
  userNames: Map<String, String>.from(_selectedUserNames),
);   // orgWide stayed TRUE
```

`RecipientResolver._computeIds()` short-circuits on `orgWide`:

```45:48:lib/services/recipient_resolver.dart
  Set<String> _computeIds() {
    if (selection.orgWide) {
      return _activeUserIds();   // ← entire organization
    }
```

So the chosen subset in `userIds` was ignored and Leader Home resolved to the
**whole organization** — the observed bug. (`toTargetSpecs` has the same
`if (orgWide) return [orgWide]` short-circuit, so an actual send would also have
gone org-wide.)

### Fix

Explicitly mark the manual selection as **not** org-wide so only the chosen users
are targeted:

```283:300:lib/screens/users_screen.dart
  void _alertSelectedUsers() {
    if (_selectedUserIds.isEmpty) return;

    // Manual selection must target ONLY the chosen users — never fall back to
    // org-wide (the constructor defaults orgWide to true).
    final recipients = AlertRecipientsSelection(
      userIds: Set<String>.from(_selectedUserIds),
      userNames: Map<String, String>.from(_selectedUserNames),
      orgWide: false,
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderHomeScreen(initialRecipients: recipients),
      ),
      (route) => false,
    );
  }
```

### Why this is correct end-to-end

With `orgWide:false` and only `userIds` set, `RecipientResolver._computeIds()`
skips `_activeUserIds()`, has no filter criteria, and adds exactly
`selection.userIds` (active, minus the sender). Therefore:

- **Recipient count** (`_resolvedRecipients.count`) = number of selected users.
- **Recipient preview / label** reflects exactly those users.
- **Send button** enabled state uses the same resolver.
- **Actual send** (`toTargetSpecs`) emits a `users` target with those IDs, and
  `AlertService` re-resolves the same set from the DB → receipts/delivery match.

No fallback to the whole organization; no reset of the selection.

### Navigation flow audited

- `users_screen.dart` → builds `AlertRecipientsSelection(... orgWide:false)` →
  `pushAndRemoveUntil(LeaderHomeScreen(initialRecipients: ...))` (single instance,
  no duplicate subscriptions).
- `leader_home_screen.dart:68` → `alertRecipients = widget.initialRecipients ?? AlertRecipientsSelection()`; resolver cache seeded from it.
- `leader_org_screen.dart` → unaffected; it builds selections via `toggle*`
  helpers which already set `orgWide:false`, and its explicit "Вся організація"
  action intentionally sets `orgWide:true`.
- `home_screen.dart:295` (admin test alert) → intentionally `AlertRecipientsSelection()` (org-wide); left unchanged.

---

## UI polish

### 1. Leader message field — now visually dominant (`leader_home_screen.dart`)
- Composer changed to **`Expanded(flex: 3)`** and history to **`Expanded(flex: 2)`**.
- The composer now occupies **~60% of the free vertical space** — clearly the
  dominant element and well above the ~24 mm target on iPhone 13/14/15
  (~300 px ≈ ~50 mm with no keyboard), while history takes the smaller ~40% share.
- Both regions are flexible, so there is **no dead space** and **no keyboard
  overflow** (both shrink when the keyboard opens; the send button stays visible).

### 2. Header alignment (`klych_components.dart` → `KlychAppHeader`, used by all roles)
- KLYCH "K" brand mark enlarged (40 → **52**) and the header row is
  `CrossAxisAlignment.center`, vertically centering the logo against the
  KLYCH title / organization / callsign / online-status block.
- Shared component, so Admin, Leader, and Member headers read as one unified
  block (role labels already removed in a prior pass).

### 3. Red button standardization (verified consistent)
- All filled red actions route through **`KlychPrimaryButton`** with
  `color: KlychTheme.alertRed` — the same component as Leader "НАДІСЛАТИ": same red
  background, auto white text, same w700 typography, same corner radius, same
  padding, same pressed state. Covered: Users "ОПОВІСТИТИ"; onboarding CTAs
  (login, create-server, invite-join, join-server, start-screen); destructive
  "ВИДАЛИТИ" text unified to the `alertRed` token. Remaining `red.shade900` usages
  are error **SnackBars**, not buttons.

### 4. User list density (`org_user_widgets.dart` → compact `UserOrgListTile`)
- Compact row collapsed from **two lines to a single line**:
  `callsign · department · status` on one row (vertical padding 7, 4 px gap).
- Roughly halves row height vs. the previous two-line compact layout → far more
  rows per screen for organizations with hundreds of users. Required fields
  (callsign, department, status) remain visible; the redundant role line was
  dropped from the dense list (still shown in the full/detail tile).

---

## Files modified

- `lib/screens/users_screen.dart` — bug fix (`orgWide:false`).
- `lib/screens/leader_home_screen.dart` — composer/history flex (dominant composer).
- `lib/widgets/org_user_widgets.dart` — single-line high-density compact user row.
- (Header logo size/centering and red-button standardization were applied in the
  preceding UI-polish passes and verified here.)

---

## Verification results

- `flutter analyze` → **no new warnings/errors**; only 6 pre-existing `info` hints
  (3 Radio/Form deprecations in `admin_user_detail_screen.dart`, 3
  `use_null_aware_elements` in `group_service.dart` / `klych_components.dart`),
  all unrelated to these changes.
- `flutter test` → **All 12 tests passed** (recipient-resolution UNION tests and
  the start-screen widget test included; no recipient-selection regressions).
