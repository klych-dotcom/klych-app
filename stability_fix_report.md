# KLYCH — Stability, Filtering & Release Readiness Pass

**Objective:** stabilize, eliminate regressions, fix filtering inconsistencies, remove performance bottlenecks, eliminate duplicate realtime behavior.
**Constraints honored:** no new features, no screen redesign, no schema/SQL/Supabase changes. Business logic touched only to fix the bugs described in the task.

**Validation:**
- `flutter analyze` → **0 errors, 0 warnings, 8 info** (all pre-existing: 3 deprecated Radio/Dropdown APIs in `admin_user_detail_screen.dart`, 5 `use_null_aware_elements` lint hints). No new issues introduced.
- `flutter test` → **All 12 tests passed** (recipient-resolution UNION tests unchanged and green).

---

## FIXED

### PART 1 — Organization filters did not affect the visible user list

**Root cause:** `LeaderOrgScreen` rendered the user list from `_searchableUsers`, which only applied the search query + `is_disabled` filter. It ignored the selected statuses/departments/groups entirely, so the list always showed the whole organization regardless of active filters.

**Fix (UNION live-preview, per clarification):** The list below the filters is now a live preview of the **exact UNION recipient set** — status ∪ department ∪ group ∪ explicit users, deduplicated — produced by the existing `RecipientResolver`. No AND/intersection, no set reduction.

- `lib/screens/leader_org_screen.dart`: replaced `_searchableUsers` with `_visibleUsers(resolved)` which returns `resolved.resolvedUsers` (the union set). When `orgWide` is active the union is the whole active org (unchanged default). When a search query is typed, the full directory is exposed so any user can still be toggled into the selection (manual selection never disables filtering).
- The build computes the resolver **once** and feeds the same instance to both the recipient count panel and the visible list, so the list and the "ОТРИМУВАЧІ (N)" count can never disagree.

Behavior now:
- Department: Headquarters → list shows Headquarters members.
- Department: Headquarters + Status: On Duty → list shows *all* Headquarters users **UNION** all On-Duty users (live recipient preview), matching delivery.

### PART 2 / P0-1 — Keyboard overflow while composing alerts

**`lib/screens/leader_home_screen.dart`:** the body is a non-scrollable `Column` with a fixed-height history list (`0.42 × screenHeight`) + `Spacer`. With the default `resizeToAvoidBottomInset: true`, opening the keyboard shrank the body and forced a RenderFlex overflow.
- **Fix:** set `resizeToAvoidBottomInset: false`. All compose controls (message field, level selector, recipients button, **send button**) live in the top ~330pt and stay above the keyboard; the history list keeps its height and is no longer squeezed. No overflow, no hidden buttons, no clipped history. Tapping anywhere still dismisses the keyboard (existing `GestureDetector`).

**`lib/screens/home_screen.dart` (Admin):** the test-alert `TextField` sat mid-`Column` with a `Spacer`; the action button directly under it would be covered by the keyboard, and the non-scrollable column overflowed on resize.
- **Fix:** wrapped the body in `SingleChildScrollView` and replaced `Spacer()` with fixed spacing. The focused field/button now scrolls into view above the keyboard; no overflow.

Verified by layout reasoning for iPhone 13 (390×844), iPhone 14 (390×844), iPhone 15 Pro (393×852): in all three the non-flexible compose content fits above the keyboard inset.

### PART 2 / P0-2 — Duplicate `LeaderHomeScreen` instances

**Root cause:** two navigation paths pushed a **new** `LeaderHomeScreen` on top of the existing one, producing duplicate alert subscriptions, duplicate `AssetsAudioPlayer`s, and duplicate alert handlers (double alarm + double full-screen alert):
1. Leader Home → **tune** → `LeaderOrgScreen()` (compose mode) → "СТВОРИТИ ОПОВІЩЕННЯ" → `Navigator.push(LeaderHomeScreen)`.
2. Leader Home → Organization → Users → "ОПОВІСТИТИ" → `Navigator.push(LeaderHomeScreen)`.

**Fixes:**
- `leader_home_screen.dart`: the **tune** button now opens `LeaderOrgScreen(selectRecipientsMode: true)` and applies the returned selection via `Navigator.pop` result — it no longer creates a second home (identical, safe pattern to the recipients button).
- `leader_org_screen.dart` `_createAlert` (compose path) now uses `Navigator.pushAndRemoveUntil(..., (route) => false)`.
- `users_screen.dart` `_alertSelectedUsers` now uses `Navigator.pushAndRemoveUntil(..., (route) => false)`.

Result: at most **one** live `LeaderHomeScreen` → one alert subscription, one audio player, one handler. The replaced screen's `dispose()` unsubscribes its channel and disposes its player.

### PART 3 — Recipient resolution recomputed multiple times per build

**`leader_home_screen.dart` & `leader_org_screen.dart`:** the resolver getter built a fresh `RecipientResolver` (a full union pass over all org users) on every access — multiple times per `build`, including on unrelated `setState` (connection-status ticks, search keystrokes).
- **Fix:** added a `_resolverCache` field; the resolver is computed lazily and reused until inputs change. `_invalidateResolver()` is called only when the selection (`_setRecipients` / recipients applied) or the underlying user/group data (`_load`, `_loadOrgTargetingData`, `_applyUserChange`) actually change. For 300–500+ user orgs this removes redundant O(n) passes from hot rebuild paths.

### PART 3 / PART 4 — Alert history reloaded on every realtime event

**`leader_home_screen.dart` & `member_home_screen.dart`:** each incoming `alerts` INSERT triggered an immediate full history refetch + `setState`, amplifying network/rebuild churn during bursts.
- **Fix:** added a 600 ms **debounced** `_scheduleHistoryReload()` (coalesces a burst into one refresh). The sender's own optimistic insert still updates instantly; realtime confirmation is debounced. Timers are cancelled in `dispose()`.

---

## VERIFIED (audited, confirmed healthy)

### PART 4 — Realtime subscription audit
- **One channel per concern, uniquely named:** `leader-alerts-$org` (`leader_home_screen.dart:194`), `member-alerts-$org` (`member_home_screen.dart:171`), `admin-alerts-$org` (`home_screen.dart` via mixin), `org-users-$org` (`user_org_service.dart:117`, only `leader_org_screen`), `alert-receipts-$alertId` (`alert_receipt_service.dart:157`, only `leader_alert_details_screen`).
- **No duplicate processing:** `AlertDeliveryTracker.tryMarkProcessed` dedupes per payload; each screen owns one tracker, and with P0-2 fixed there is only one alert-handling screen per role at a time.
- **No orphan channels / leaks:** every `RealtimeChannel` is unsubscribed in `dispose()` (`leader_home`, `member_home`, `home_screen` via `disposeAlertRealtime`, `leader_org`, `leader_alert_details`). All `AssetsAudioPlayer` and `TextEditingController` instances are disposed. New debounce `Timer`s are cancelled in `dispose()`.

### PART 5 — Acknowledgement flow
- `AlertReceiptService.createReceiptsForAlert` inserts one row per intended recipient at creation time.
- Member presses **"ПІДТВЕРДИТИ ОТРИМАННЯ"** → `AlertScreen._confirmReceipt` → `markAcknowledged`, which writes `acknowledged_at` and backfills `opened_at`/`delivered_at` if null (`alert_receipt_service.dart:116-141`). `markDelivered`/`markOpened` set their timestamp only if currently null (idempotent).
- Leader visibility: `LeaderAlertDetailsScreen` loads receipts (`fetchForAlert`) and **subscribes to `alert_receipts` realtime** with a 300 ms debounced reload, so recipient / delivered / acknowledged status + acknowledgement timestamp update live with **no stale cache**. History tiles show `✓ confirmed/total` from `fetchAckStatsForAlerts` (batched, no N+1).

### PART 6 — Error handling
- **No empty catch blocks** anywhere in the codebase (grep verified).
- User-facing flows surface failures via SnackBars (`sendAlert`, status update, group/department/user mutations, auth screens). Background best-effort operations (`markDelivered`, history reloads, targeting prefetch) log with `debugPrint` and degrade gracefully.
- Minor improvement: replaced two bare `debugPrint('$e')` logs in `leader_home_screen._loadOrgTargetingData` and `leader_org_screen._load` with prefixed messages for traceability. No noisy logging added.

### PART 7 — Release readiness spot-check (by flow/code path)
- **Admin:** create org, invites (create/regenerate via `_loadInvites`/`regenerateInviteCode`), user management, departments, test alerts — paths intact; admin receives targeted alerts via the realtime mixin.
- **Leader:** recipients/departments/statuses/groups/multi-select targeting (UNION) now reflected in the live preview list; history (optimistic + debounced realtime); acknowledgement visibility via details screen.
- **Member:** login, status change, realtime alert reception, acknowledgement, DB-backed history — intact.

---

## REMAINING (not blocking; deferred to the UI/UX phase)

- **P2 — Legacy styling not on `KlychTheme`:** `group_details_screen.dart`, `profile_screen.dart`, `admin_user_detail_screen.dart`, `alert_screen.dart` and several dialogs still use hardcoded colors. Cosmetic only; slated for the dedicated UI/UX pass.
- **P2 — Deprecated widget APIs:** `admin_user_detail_screen.dart` `RadioListTile.groupValue/onChanged` and `DropdownButtonFormField.value` (analyzer info). Compiles/runs today; should migrate before a future SDK bump.
- **P2 — `login_screen.dart` has no scroll view** (uses `Spacer`s). Fits at default text size on the target devices but is not robust to large accessibility fonts; align with the other auth screens (which use `SingleChildScrollView`) during UI polish.
- **P2 — Fixed-fraction history height** (`0.42 × screenHeight`) on leader/member home is fragile to text scaling; acceptable now, revisit in UI pass.
- **Note — Organization preview vs. self-exclusion:** the org-screen recipient count includes the leader themselves, while actual delivery excludes the sender (`excludeUserId`). Cosmetic count difference of at most 1; left unchanged to avoid altering targeting logic.

---

## PERFORMANCE NOTES (before → after)

| Area | Before | After |
|------|--------|-------|
| Recipient resolution | Full union pass rebuilt multiple times per `build`, incl. on search keystrokes & connection ticks | Computed once per selection/data change (cached + invalidated); reused across rebuilds |
| Organization screen list | Rendered full org regardless of filters; misleading | Renders exact union recipient set, single resolver instance shared with the count |
| Alert history (leader/member) | Full network refetch + `setState` on **every** realtime insert | Debounced (600 ms) single refresh per burst; optimistic insert still instant |
| Realtime subscriptions | Possible 2× `LeaderHomeScreen` → 2× channels / players / handlers (double alarm) | Guaranteed single instance → single channel/player/handler |
| Org user updates | Already per-user patch (no full reload) — confirmed; now also invalidates resolver cache precisely | Unchanged (healthy) |
| Keyboard compose | RenderFlex overflow on Leader & Admin home | No overflow; controls remain reachable |

---

## RELEASE RECOMMENDATION

**READY FOR UI POLISHING.**

Reasoning: both P0 release blockers (keyboard overflow, duplicate Leader screen / duplicate alarm) are resolved; the critical Organization filtering bug is fixed with consistent UNION live-preview semantics; recipient resolution and history refresh are no longer redundant; realtime is single-subscription with clean disposal; and the acknowledgement path is verified end-to-end with live, non-stale leader visibility. `flutter analyze` is clean of errors/warnings and all tests pass. Remaining items are P2 cosmetic/robustness points appropriate for the dedicated UI/UX refinement phase.
