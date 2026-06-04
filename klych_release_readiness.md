# KLYCH — Final Release Readiness Audit

**Scope:** Static + structural review of Leader, Admin, Member flows.
**Targets:** iPhone 13 (390×844), iPhone 14 (390×844), iPhone 15 Pro (393×852).
**Mode:** Audit only — no features implemented, no code changed.

**Static analysis:** `flutter analyze` → **0 errors, 0 warnings, 8 info** (deprecations + lint hints only).

> Note: Layout-overflow / RenderFlex / keyboard issues are **runtime** behaviors and cannot be surfaced by `flutter analyze`. The findings below are derived from widget-tree structure (which columns are scrollable, which heights are fixed, where text fields trigger the keyboard) reasoned against the three target screen sizes.

---

## Severity legend

- **P0** — Release blocker. Breaks core emergency function or produces user-visible failure on target devices.
- **P1** — High. Visible defect / reliability risk under normal use; fix before wide rollout.
- **P2** — Medium/low. Polish, edge cases, tech debt; safe to ship but should be scheduled.

---

## P0 — Release blockers

### P0-1 — Keyboard opens RenderFlex overflow on Leader Home (compose) and Admin Home

**Files:**
- `lib/screens/leader_home_screen.dart:482-642` (non-scrollable `Column`, `TextField` at `:526`, fixed history `SizedBox(height: MediaQuery.sizeOf(context).height * 0.42)` at `:598-599`, `Spacer()` at `:641`)
- `lib/screens/home_screen.dart:452-566` (non-scrollable `Column`, `TextField` at `:499`, two invite cards + 3 buttons + `Spacer()` at `:554`)

**Problem:** Both home screens lay out their content in a bare `Column` inside `SafeArea` (no `SingleChildScrollView` / scroll view). `Scaffold.resizeToAvoidBottomInset` defaults to `true`, so when the user taps the alert-message `TextField` the body shrinks by the keyboard height (~290–340pt on the target devices).

On the target devices the non-flexible children no longer fit:
- **Leader Home:** top compose block (~300pt) + history `SizedBox` fixed at `0.42 × 844 ≈ 354pt` = ~654pt of *non-flexible* content vs. ~470pt available with the keyboard up → the `Spacer` collapses to 0 and the `Column` overflows by ~180pt (black/yellow overflow stripe + clipped history). The history `SizedBox` uses `0.42 ×` **full screen height**, not the keyboard-constrained height, so it cannot shrink.
- **Admin Home:** header + 2 invite cards + 2-line `TextField` + 3 buttons + footer is ~720pt of non-flexible content vs. ~470pt available → overflow of ~250pt.

**Impact:** The primary action screen for the two alert-sending roles visibly breaks layout the moment the operator types an alert message — directly on the listed devices. For an emergency tool this is a blocker.

**Direction (not applied):** Wrap the body in a scroll view, or make the history list `Expanded` (flex) instead of a `MediaQuery`-fraction `SizedBox`, and/or set `resizeToAvoidBottomInset: false` only if combined with a scroll view.

---

### P0-2 — Duplicate `LeaderHomeScreen` instances → duplicated realtime subscription, duplicated alarm, double full-screen alert

**Files:**
- `lib/screens/leader_home_screen.dart:506-514` ("tune" icon pushes `LeaderOrgScreen()` in **compose** mode, not select mode)
- `lib/screens/leader_org_screen.dart:145-150` (`_createAlert()` in non-select mode **pushes a new `LeaderHomeScreen`**)
- `lib/screens/users_screen.dart:283-297` (`_alertSelectedUsers()` also pushes a new `LeaderHomeScreen`)
- Subscription created in `leader_home_screen.dart:194` (`supabase.channel('leader-alerts-$orgId')`); audio player at `:37`.

**Problem:** Navigation can stack multiple live `LeaderHomeScreen` instances. Path: Leader Home → tap **tune** (`:506`) → `LeaderOrgScreen` → **СТВОРИТИ ОПОВІЩЕННЯ** (`leader_org_screen.dart:145`) pushes a *second* `LeaderHomeScreen` on top of the first. Both instances stay mounted and each:
- opens its own `leader-alerts-$orgId` Postgres-changes subscription (`:194`),
- holds its own `AssetsAudioPlayer` (`:37`),
- holds its own `AlertDeliveryTracker` (`:58`), so the dedup guard does **not** cross instances.

When an alert arrives, **both** handlers fire (`_handleIncomingAlert`, `:218`): two `markDelivered` calls, two alarm audio streams, and two stacked `AlertScreen` full-screen dialogs.

**Impact:** For a life-safety alarm app, duplicated alarms / double full-screen takeovers and duplicated realtime processing is a correctness + reliability failure. Violates the "no duplicated realtime subscriptions" release criterion.

**Direction (not applied):** From `LeaderOrgScreen` compose flow, return the selection via `Navigator.pop(context, _recipients)` (as select mode already does at `:140-142`) instead of pushing a new home; or use `pushReplacement`.

---

## P1 — High

### P1-1 — Full history refetch on every incoming realtime insert (rebuild/network amplification)

**Files:**
- `lib/screens/leader_home_screen.dart:222` (`await _loadAlertHistory()` inside `_handleIncomingAlert`, before the recipient check)
- `lib/screens/member_home_screen.dart:211` (same pattern)

**Problem:** Each `alerts` INSERT event triggers a complete `fetchOrgAlertHistory` / `fetchUserAlertHistory` round-trip + `setState`. During a burst (multiple alerts, or an alert plus its own optimistic insert) this produces repeated network calls and list rebuilds. Not an infinite loop, but unnecessary churn that can cause perceptible jank on the history list.

**Direction:** Debounce/coalesce refreshes, or patch the single new row into the list instead of refetching the whole history.

### P1-2 — Login screen has no scroll view (keyboard overlap risk on target devices)

**File:** `lib/screens/login_screen.dart:98-185` — `Column` with `Spacer()`s (`:124`, `:182`) and two `TextField`s (`:135`, `:142`), no `SingleChildScrollView`.

**Problem:** Unlike `invite_join_screen.dart` and `create_server_screen.dart` (both correctly wrapped in `SingleChildScrollView`), the login screen relies on `Spacer`s. With the keyboard up the fixed content (large "ВХІД" title 40pt + two fields + 64pt button + back button) is close to the available height; with the system text size increased it overflows. Inconsistent with the other auth screens.

**Direction:** Wrap body in `SingleChildScrollView` to match the other onboarding screens.

---

## P2 — Medium / Low

### P2-1 — Member Home history uses fixed `0.42 × screenHeight`; fragile to large text / smaller devices
`lib/screens/member_home_screen.dart:496-497`. No keyboard on this screen (no text field), so it does not overflow on the three target devices at default text size, but the magic fraction is not robust to accessibility text scaling. Prefer `Expanded`.

### P2-2 — Recipient resolution recomputed multiple times per build over all org users
`lib/screens/leader_home_screen.dart:90-99` and `:562`/`:574` call the `_resolvedRecipients` getter (which builds a fresh `RecipientResolver` and unions across **all** org users) more than once per `build`, including on connection-status `setState`. O(n) per rebuild; negligible for small orgs, wasteful at 300–500+ users. Cache the resolver per selection change.

### P2-3 — Cross-role visual inconsistency (legacy hardcoded styling not migrated to `KlychTheme`)
`lib/screens/group_details_screen.dart` (e.g. `:278` `0xFF0F0F10`, `Colors.red`), `lib/screens/profile_screen.dart:82-145`, `lib/screens/admin_user_detail_screen.dart:96-156`, `lib/screens/alert_screen.dart:76` and dialogs across `leader_home_screen.dart:395`, `member_home_screen.dart:336`. These still use raw colors / `Color(0xFF1C1C1E)` instead of the unified `KlychTheme`. Cosmetic; breaks the "same product feel" goal but not function.

### P2-4 — Deprecated Flutter widget APIs (from `flutter analyze`)
`lib/screens/admin_user_detail_screen.dart:119` (`RadioListTile.groupValue`), `:120` (`onChanged`), `:128` (`DropdownButtonFormField.value`). Deprecated after Flutter 3.32/3.33 (`RadioGroup` / `initialValue`). Still compiles and runs; will break on a future SDK bump.

### P2-5 — `AlertScreen` body is non-scrollable; very long alert text can overflow
`lib/screens/alert_screen.dart:80-136` — `Column(mainAxisAlignment: center)` + `Spacer()` with a fixed 120pt icon, 42pt title and 70pt button. Typical messages are short and fit, but an unusually long `message` has no scroll fallback and would overflow vertically.

### P2-6 — Lint hints (`use_null_aware_elements`)
`lib/services/group_service.dart:254,274`, `lib/widgets/klych_components.dart:82`, `lib/widgets/org_user_widgets.dart:112,155`. Style only.

### P2-7 — Logout navigation target differs by role
Member logout → `JoinServerScreen` (`member_home_screen.dart:393-396`); Leader → `StartScreen` (`leader_home_screen.dart:426-430`); Admin → `StartScreen`. All valid destinations, but inconsistent landing for the same action.

---

## Verified clean (no findings)

- **Memory / subscription leaks:** All stateful screens dispose correctly — realtime channels unsubscribed and players/controllers disposed in `dispose()`: `leader_home_screen.dart:466-472`, `member_home_screen.dart:427-434`, `home_screen.dart:56-61` (`disposeAlertRealtime`), `leader_org_screen.dart:47-52`, `profile_screen.dart:28-32`, `login_screen.dart:23-28`, `invite_join_screen.dart:35-42`, `create_server_screen.dart:24-30`. No undisposed `RealtimeChannel`/`AssetsAudioPlayer`/`TextEditingController` found.
- **Channel-name uniqueness (single-instance case):** `leader-alerts-$org`, `member-alerts-$org`, `admin-alerts-$org`, `org-users-$org`, `alert-receipts-$alertId` are distinct per role/scope. (The only duplication risk is the stacked-instance case in **P0-2**.)
- **Loading loops:** No `setState`/future loops in `build`. All `RefreshIndicator`s are wired to real one-shot futures (`leader_home_screen.dart:600`, `member_home_screen.dart:498`, `users_screen.dart:352`, `departments_screen.dart:233`, `leader_org_screen.dart:190`).
- **Keyboard-safe screens:** `invite_join_screen.dart` and `create_server_screen.dart` use `SingleChildScrollView`; `leader_org_screen.dart` and `users_screen.dart` use `Expanded` + `ListView` with a fixed bottom action panel (correct, keyboard shrinks the list).
- **Navigation:** All `Navigator.push`/`pop`/`pushAndRemoveUntil` paths resolve to existing routes; back buttons handle the `canPop == false` case (`login_screen.dart:107`, `invite_join_screen.dart:261`, `create_server_screen.dart:155`).

---

## Recommended gate before release

| Item | Severity | Must fix to ship? |
|------|----------|-------------------|
| P0-1 Keyboard overflow (Leader/Admin home) | P0 | Yes |
| P0-2 Duplicate LeaderHome subscription/alarm | P0 | Yes |
| P1-1 History refetch amplification | P1 | Recommended |
| P1-2 Login no scroll view | P1 | Recommended |
| P2-1 … P2-7 | P2 | Schedule post-release |

No new features were implemented; this document is audit output only.
