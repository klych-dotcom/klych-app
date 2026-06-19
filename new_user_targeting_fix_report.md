# KLYCH — New-User Targeting Fix + Minor UI Adjustment

Scope: fix the stale recipient/targeting cache so newly-joined users are
immediately targetable, plus reduce the Leader Home message field height.
No schema, SQL, RLS, alert pipeline, targeting logic, realtime, receipts, or
acknowledgement code was modified.

---

## BUG — New user cannot be targeted by an existing leader (FIXED)

### Root cause

`leader_home_screen.dart` loads its org-users snapshot **once at init** and never
refreshes it, while the recipient-selection screen loads fresh data:

- `leader_org_screen.dart` (where the leader picks recipients) loads fresh users
  on open **and** subscribes to user changes:
  ```59:81:lib/screens/leader_org_screen.dart
    Future<void> _load() async {
      ...
        users = await UserOrgService.fetchOrgUsers(organizationId!);
        ...
        _invalidateResolver();
  ```
  → so it correctly shows and lets the leader select a newly-joined user.

- `leader_home_screen.dart` loads `orgUsers` once (`_loadOrgTargetingData` at
  init), subscribes only to `alerts` (no users subscription), and on
  selection-return it previously just did `setState` against that **stale**
  snapshot.

The resolver matches explicit user IDs against the in-memory `users` snapshot:

```65:73:lib/services/recipient_resolver.dart
    for (final uid in selection.userIds) {
      final user = users.cast<Map<String, dynamic>?>().firstWhere(
            (u) => u?['id']?.toString() == uid,
            orElse: () => null,
          );
      if (user != null && user['is_disabled'] != true) {
        matched.add(uid);
      }
    }
```

A user who joined **after** Leader Home first loaded is absent from
`leader_home_screen.orgUsers`, so the resolver finds no matching row, drops the
ID, and `count` becomes 0. Logout/login rebuilds the snapshot from scratch, which
is why it "fixed itself" after re-login.

(The stale snapshot is purely a UI/gating problem: `AlertService.createAlert`
re-fetches users from the DB on send, but the disabled Send button — gated by
`_resolvedRecipients.canSend` — blocks the leader before that point.)

### Fix — targeted cache refresh on selection return

Both recipient-selection entry points (the `tune` icon and the recipients button)
now route their result through a single helper that refreshes the targeting
dataset **before** resolving, then invalidates only the resolver cache:

```lib/screens/leader_home_screen.dart
  Future<void> _applyRecipientResult(AlertRecipientsSelection? result) async {
    if (result == null || !mounted) return;
    await _loadOrgTargetingData();   // refresh orgUsers/orgGroups snapshot
    if (!mounted) return;
    setState(() {
      alertRecipients = result;
      _invalidateResolver();         // recompute against fresh data
    });
  }
```

`_loadOrgTargetingData()` re-fetches `orgUsers` + `orgGroups` and invalidates the
resolver. Because `LeaderOrgScreen` already shows fresh data, refreshing exactly
at the moment the selection returns guarantees the Home screen resolves the same
set the leader just chose — including any newly-joined user.

This is **not** a full screen reload (no `loading` state, no rebuild of history /
subscriptions); it refreshes only the targeting dataset cache and the resolver
cache, on demand.

### Result
- New users become targetable instantly — no logout/login.
- Recipient **count** and **preview** update correctly (resolver recomputes
  against the refreshed snapshot).
- Send button enables and the alert can be sent immediately.
- No change to targeting logic, realtime, receipts, or the alert pipeline.

---

## UI ADJUSTMENT — Leader Home message field

The composer had become the dominant region (`Expanded(flex: 3)`, ~60% of free
vertical space). It is now a fixed **150 px** comfortable multi-line area
(~50% smaller), and the alert history takes the remaining space:

- Composer: `Expanded(flex: 3)` → `SizedBox(height: 150)` wrapping the same
  `TextField(expands: true)` (styling/behavior unchanged).
- History: `Expanded(flex: 2)` → plain `Expanded` (fills the freed space → more
  room for recipients/history).
- No other layout proportions changed; still keyboard-safe (history flexes, the
  fixed composer + send button stay visible, no overflow).

---

## Files modified

- `lib/screens/leader_home_screen.dart`
  - Added `_applyRecipientResult(...)` (refresh targeting snapshot + invalidate
    resolver) and routed both selection-return sites through it.
  - Message composer reduced from `Expanded(flex: 3)` to `SizedBox(height: 150)`;
    history changed from `Expanded(flex: 2)` to `Expanded`.

(No other files changed.)

---

## Cache invalidation changes

| Cache | Before | After |
|-------|--------|-------|
| `orgUsers` / `orgGroups` snapshot (Home) | Loaded once at init; stale on new joins | Refreshed on every recipient-selection return |
| `RecipientResolver` cache (`_resolverCache`) | Invalidated on selection set only | Invalidated after the snapshot refresh, so it recomputes against fresh data |

Only the affected caches are touched; no full reloads, no realtime changes.

---

## Verification results

- `flutter analyze` → no new warnings/errors; only 6 pre-existing `info` hints
  (Radio/Form deprecations in `admin_user_detail_screen.dart`,
  `use_null_aware_elements` in `group_service.dart` / `klych_components.dart`).
- `flutter test` → **All 12 tests passed** (recipient-resolution UNION tests
  included; no targeting regressions).
- Behavior: selecting a newly-joined user now yields a correct non-zero recipient
  count/preview and an enabled Send button without re-login.
