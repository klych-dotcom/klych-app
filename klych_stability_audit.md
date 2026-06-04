# KLYCH Stability & Completion Audit

**Date:** 2026-05-31  
**Scope:** Flutter client audit only — no schema changes, no new features implemented  
**Method:** Static code-path inspection of all `lib/` sources and v2 schema references

---

## Executive summary

Recent feature packs are **substantially implemented** at the UI and service layer, but several **critical gaps** remain between intended behavior and runtime behavior — especially **alert delivery vs targeting**, **acknowledgement completeness**, and **performance under realtime load**.

| Area | Completion | Stability |
|------|------------|-----------|
| Departments | Complete | Good |
| Groups | Complete | Good (with perf caveats) |
| Leader targeting (UI) | Complete | Good |
| Alert targeting (delivery) | **Incomplete** | **Broken semantics** |
| Alert receipts / ack | **Partial** | **Fragile** |
| Alert history | **Partial** (local only) | Device-bound |
| Realtime | Partial | Perf risk on org screen |

---

## PART 1 — Feature Completion Audit

### Departments ✅ Complete

| Operation | Service | UI | Status |
|-----------|---------|-----|--------|
| Create | `DepartmentService.create()` | `DepartmentsScreen._createDepartment` | ✅ Restores archived duplicate names |
| Rename | `DepartmentService.rename()` | `_renameDepartment` | ✅ Duplicate-name guard |
| Archive | `DepartmentService.archive()` | `_archiveDepartment` | ✅ |
| Restore | `DepartmentService.restore()` | `_restoreDepartment` | ✅ |

**Notes:** UI shows localized labels via `DepartmentLabels`; DB stores English seed names. Errors surfaced via `DbErrorMessages` + SnackBar.

---

### Groups ✅ Complete (management hub pattern)

| Operation | Location | Status |
|-----------|----------|--------|
| Create | `UsersScreen` → `GroupService.createGroupWithMembers` | ✅ Error handling + verify fetch |
| Rename | `GroupDetailsScreen` | ✅ |
| Delete | `GroupDetailsScreen` (confirm dialog) | ✅ Deletes `group_members` then group |
| Add members | `GroupDetailsScreen`, `UsersScreen` bulk | ✅ |
| Remove members | `GroupDetailsScreen` | ✅ Confirm dialog |
| View list | `GroupsScreen` → `GroupDetailsScreen` | ✅ |
| Persistence | Supabase `operational_groups` + `group_members` | ✅ Survives restart |

**Notes:** Organization screen correctly does **not** manage membership. `GroupService.fetchGroups` uses explicit FK embed `users!group_members_user_id_fkey` (fixes prior silent fetch failure).

**Gap (P2):** `addMembers` does not skip users already in group — duplicate insert throws `23505` (shown to user, not silent).

---

### Leader targeting — UI ✅ / Delivery ❌

| Feature | UI (`LeaderOrgScreen`) | Persisted (`alert_targets`) | Delivered to clients |
|---------|------------------------|----------------------------|----------------------|
| Status filter | ✅ Multi-select chips | ✅ `status` rows | ❌ Org-wide |
| Department filter | ✅ | ✅ `department` rows | ❌ Org-wide |
| Group filter | ✅ | ✅ `group` rows | ❌ Org-wide |
| User multi-select | ✅ Highlight + toggle | ✅ `users` + `alert_target_users` | ❌ Org-wide |
| Combined filters (AND) | ✅ Intersection list + count | ✅ Multi-row or resolved `users` | ❌ Org-wide |
| Manual user override | ✅ | ✅ | ❌ Org-wide |

**Root cause:** `AlertUtils.shouldReceiveAlert()` only checks `organization_id`:

```41:46:lib/utils/alert_utils.dart
  static bool shouldReceiveAlert(
    Map<String, dynamic> alert,
    String organizationId,
  ) {
    return alert['organization_id']?.toString() == organizationId.toString();
  }
```

`AlertTargeting.serverSideEnabled = true` in `lib/models/alert_targeting.dart`, but **no server-side or client-side recipient filtering** is applied on receive. All org members get RED/GREEN notifications regardless of filters.

---

### Recipient calculation — UI ✅ / Stale data ⚠️

| Scenario | `AlertRecipientsSelection` | Verified |
|----------|---------------------------|----------|
| No filters | All non-disabled users | ✅ |
| Single category multi-select | OR within category | ✅ |
| Multi-category | AND across categories | ✅ |
| Manual users selected | Count = selected only | ✅ |
| Combined filters + manual | Manual overrides count | ✅ |

**Gaps:**
- **P2:** `LeaderHomeScreen` loads `orgUsers`/`orgGroups` once at init — recipient count on home card can be **stale** after status/department changes until screen rebuild/revisit.
- **P3:** Org-wide count includes sender; receipt fan-out **excludes** sender — off-by-one in display vs receipts.

---

### Alert creation ✅ (insert) / ⚠️ (atomicity)

| Level | Path | DB writes |
|-------|------|-----------|
| RED | `LeaderHomeScreen.sendAlert` | `alerts`, `alert_targets`, `alert_receipts` |
| GREEN | Same | Same |
| Admin test | `HomeScreen.testAlert` | Same (`is_test: true`) |

**Gap (P0):** No transaction — if `AlertReceiptService.createReceiptsForAlert` throws after alert + targets inserted, DB is left **partially committed** (`alert_service.dart` lines 31–73).

---

### Alert history — ⚠️ Partial (local only)

| Role | Storage | Server query | Ack linkage |
|------|---------|--------------|-------------|
| Leader | `SharedPreferences` `leader_alerts_history` | None | Details screen queries `alert_receipts` by alert `id` |
| Member | `SharedPreferences` `alerts_history` | None | None |

**Gaps:**
- History lost on reinstall / new device (P1).
- Realtime-received alerts may lack `target_label` (only set on send response) (P2).
- Member has no acknowledgement UI in history list (P3).

---

## PART 2 — Alert Acknowledgement Audit

### Current code path: “Підтвердити отримання”

**Button location:** `lib/screens/alert_screen.dart` (RED fullscreen alert)

| Step | Code | DB write |
|------|------|----------|
| Screen opens | `initState` → `AlertReceiptService.markOpened` | `opened_at` (insert row if missing) |
| Button tap | `_confirmReceipt` → `markAcknowledged` | `acknowledged_at`; backfills `opened_at`/`delivered_at` if null |
| Then | Stop audio, `Navigator.pop` | — |

**Requires:** `alert['id']` and `userId` passed to `AlertScreen`. Local test alerts without DB id **skip all writes** (`alert_screen.dart` lines 37–38).

### Receipt fan-out on send

`AlertService.createAlert` → `AlertReceiptService.createReceiptsForAlert` for `recipients.resolveDeliveryUserIds()` **excluding sender** (`alert_service.dart` lines 65–73).

### Member receive path

`MemberHomeScreen._handleIncomingAlert`:
1. Local history write (`SharedPreferences`)
2. `AlertReceiptService.markDelivered` (if alert has id)
3. RED → `AlertScreen` / GREEN → SnackBar with “ПІДТВЕРДИТИ” action

### Timestamp columns — actual behavior

| Column | When set | Who |
|--------|----------|-----|
| `delivered_at` | Realtime receive (member) | `member_home_screen.dart` |
| `opened_at` | AlertScreen open; green ack shortcut | `alert_screen.dart`, member green SnackBar |
| `acknowledged_at` | Confirm button / green ack | `alert_screen.dart`, member green SnackBar |

**`_setTimestamp` / `_ensureRow`:** If no pre-created row exists, member can **insert orphan receipt** via `_ensureRow` — users not in intended recipient list may get receipt rows if they received org-wide broadcast (P1 data inconsistency).

### Does leader see acknowledgement data?

**Yes, partially:**

| Access | Screen | Condition |
|--------|--------|-----------|
| Per-alert recipient list | `LeaderAlertDetailsScreen` | Alert has `id`; tap from `LeaderHomeScreen` history |
| Realtime updates | Receipt subscription on details screen | ✅ `subscribeToAlertReceipts` |
| Summary on home list | None | ❌ No ack counts on list rows |
| Server alert history | None | ❌ Local prefs only |

**Leader-as-recipient gaps (P1):**
- `LeaderHomeScreen._handleIncomingAlert` does **not** call `markDelivered` (member does).
- Leader GREEN SnackBar has **no** ack action (member has “ПІДТВЕРДИТИ”).
- Leader RED uses `AlertScreen` → ack works if alert has id.

### Acknowledgement status semantics

`ReceiptDisplayStatus`:
- ✓ Confirmed = `acknowledged_at` set
- ⏳ Waiting = `opened_at` set, no ack
- ❌ Not opened = neither ( **`delivered_at` alone still shows Not opened** )

---

## PART 3 — Realtime Audit

| Table | Subscriber | Events | Disposed |
|-------|------------|--------|----------|
| `alerts` | `LeaderHomeScreen`, `MemberHomeScreen` | INSERT by org | ✅ `dispose()` |
| `users` | `LeaderOrgScreen` only | UPDATE by org | ✅ |
| `alert_receipts` | `LeaderAlertDetailsScreen` | ALL by alert_id | ✅ |
| `operational_groups` | — | — | — |
| `group_members` | — | — | — |

### Issues

| Issue | Severity | Detail |
|-------|----------|--------|
| Org user subscription reload storm | **P1** | Every `users` UPDATE triggers full `_load()`: users + departments + `fetchGroups` N+1 (`leader_org_screen.dart` lines 66–70) |
| No debounce on receipt reload | **P2** | Each receipt UPDATE refetches entire list (`leader_alert_details_screen.dart` line 55) |
| User INSERT not subscribed | **P3** | New members don’t appear on org screen until manual refresh |
| No duplicate channel leak found | — | All channels unsubscribed in `dispose()` |
| Leader + member dual subscribe | — | Only if same account on two devices; not a code bug |

---

## PART 4 — Performance Audit

### High-impact patterns

| Risk | Location | Impact |
|------|----------|--------|
| **N+1 group member queries** | `GroupService.fetchGroups` — 1 query per group | Called on: org screen load, every user realtime update, alert send, users screen load |
| **Full org reload on status change** | `LeaderOrgScreen._subscribe` → `_load()` | UI freeze/lag when any member updates status |
| **Sequential alert target inserts** | `AlertService.createAlert` loop | Slow sends with many targets |
| **Triple query per receipt timestamp** | `AlertReceiptService._setTimestamp` — ensure + fetch + update | Latency on ack path |
| **Spread `...filteredUsers.map` in build** | `LeaderOrgScreen` ListView children | Rebuilds all compact tiles on every filter toggle |
| **Duplicate user/org fetch on send** | `AlertService` fetches users+groups; receipt label reuses same | Acceptable but redundant with targeting fetch |

### Not found

- No nested `FutureBuilder` loops (only `main.dart` startup FutureBuilder — correctly cached).
- No infinite refresh loops detected.
- `AlertDeliveryTracker` prevents duplicate alert UI/history processing ✅

---

## PART 5 — Error Handling Audit

### Silent / swallowed failures (`debugPrint` only, no user feedback)

| File | Lines | Context |
|------|-------|---------|
| `leader_org_screen.dart` | 56–58 | Full org load failure — screen may show empty/stale data |
| `leader_home_screen.dart` | 77, 117, 132, 141, 228, 330 | User load, org data, alert handling, logout |
| `member_home_screen.dart` | 92, 129, 139, 158, 225, 261, 298 | User load, alerts, receipt marks |
| `users_screen.dart` | 59 | User list load |
| `groups_screen.dart` | 38 | Group list load |
| `group_details_screen.dart` | 45 | Initial load (mutations show SnackBar) |
| `leader_alert_details_screen.dart` | 41 | Receipt fetch failure — shows empty list |
| `alert_screen.dart` | 43, 68 | Open/ack write failures — user sees no error |
| `profile_screen.dart` | 43 | Profile load |

### Properly surfaced (SnackBar / thrown Exception)

- `departments_screen.dart` — all mutations ✅
- `users_screen.dart` — group create/add ✅
- `group_details_screen.dart` — rename/delete/member mutations ✅
- `GroupService` / `AlertReceiptService.createReceiptsForAlert` — throws on PostgREST error ✅
- `leader_home_screen.dart` — `sendAlert` catch shows SnackBar ✅

---

## PART 6 — State Management Audit

| Screen | State | Survives navigation | Issues |
|--------|-------|---------------------|--------|
| `LeaderOrgScreen` | `_recipients`, filters | ✅ Push to Groups/Users and pop | Realtime `_load` may reset UX mid-selection (no explicit reset) |
| `LeaderHomeScreen` | `alertRecipients` | ✅ Pop from org with `selectRecipientsMode` | Recipient count data stale (P2) |
| `LeaderHomeScreen` | — | ⚠️ | Org “СТВОРИТИ ОПОВІЩЕННЯ” **pushes** new `LeaderHomeScreen` instead of popping — stack duplication (`leader_org_screen.dart` line 93–97) |
| `UsersScreen` | `_selectedUserIds` | ✅ Cleared after group actions | Selection lost on navigate away (expected) |
| `GroupsScreen` | — | Reloads after details | ✅ |

**Filter + user selection:** `pruneUsersToVisible` correctly drops manual picks when filters change ✅

---

## PART 7 — Findings by Priority

### P0 — Crashes / data loss / broken core semantics

| # | Finding | Evidence |
|---|---------|----------|
| P0-1 | **Alert delivery ignores targeting** — filtered alerts notify entire org | `alert_utils.dart` `shouldReceiveAlert` |
| P0-2 | **Non-atomic alert send** — alert/targets committed before receipts; receipt failure leaves orphan alert | `alert_service.dart` no rollback |
| P0-3 | **Receipt vs delivery mismatch** — receipts for subset, notifications for org | Send fan-out vs receive filter |

### P1 — Broken / incomplete functionality

| # | Finding | Evidence |
|---|---------|----------|
| P1-1 | Acknowledgement **not connected for leader-as-recipient** (no `markDelivered`, no green ack) | `leader_home_screen.dart` |
| P1-2 | **Alert history local-only** — no server sync, lost on reinstall | `leader_home_screen.dart`, `member_home_screen.dart` SharedPreferences |
| P1-3 | **Orphan receipt rows** — non-targeted users can insert receipts via `_ensureRow` on org-wide receive | `alert_receipt_service.dart` |
| P1-4 | **Org screen realtime reload storm** — full refetch + N+1 groups on every user UPDATE | `leader_org_screen.dart` |
| P1-5 | **Ack write failures silent** to user on member/leader alert screen | `alert_screen.dart` catch blocks |
| P1-6 | **Alert details empty** for alerts without DB `id` or pre-receipt-era alerts | `leader_alert_details_screen.dart` |

### P2 — Performance issues

| # | Finding | Evidence |
|---|---------|----------|
| P2-1 | `GroupService.fetchGroups` N+1 on every org load / alert send | `group_service.dart` |
| P2-2 | Stale recipient count on `LeaderHomeScreen` | `_loadOrgTargetingData` once at init |
| P2-3 | Receipt realtime triggers full refetch without debounce | `leader_alert_details_screen.dart` |
| P2-4 | Leader navigation stack duplication (Home → Org → Home) | `leader_org_screen.dart` |
| P2-5 | Sequential per-target DB inserts on alert send | `alert_service.dart` |

### P3 — UX improvements

| # | Finding |
|---|---------|
| P3-1 | No ack summary on leader alert history rows |
| P3-2 | `delivered_at` without `opened_at` shows “Not opened” — no “delivered” state |
| P3-3 | Member history has no ack affordance |
| P3-4 | New users don’t appear on org screen until refresh (UPDATE-only subscription) |
| P3-5 | `AlertTargeting.serverSideEnabled = true` contradicts actual client behavior — misleading flag |
| P3-6 | Local member “ЛОКАЛЬНИЙ ТЕСТ” bypasses receipt/ack pipeline |

---

## Recommended fixes (audit only — not implemented)

### Phase A — Correctness (address P0–P1 first)

1. **Client-side recipient filtering** on receive: resolve alert targets (or check receipt row existence) before showing RED/GREEN UI — align with `alert_targets` / `alert_receipts`.
2. **Wrap alert send** in compensating logic: if receipt fan-out fails, surface error clearly; consider delete alert or retry receipts.
3. **Unify ack path** on leader home: `markDelivered` on receive, green SnackBar ack, same as member.
4. **Only update receipts for intended recipients** — don’t `_ensureRow` for users without a fan-out row (or create fan-out for all org receivers consistently).
5. **Debounce/throttle org screen reload** — patch user in local list instead of full `_load()` + `fetchGroups`.

### Phase B — Performance (P2)

1. Batch group member fetch (single query or embedded select on `operational_groups`).
2. Cache org users/groups on leader home with invalidation on org screen return.
3. Debounce receipt details reload (300–500 ms).
4. Fix org → home navigation to `pop` with recipients instead of pushing duplicate home.

### Phase C — UX / completeness (P3)

1. Server-backed alert history (or fetch recent alerts from Supabase).
2. Ack badge on leader history list (`confirmed / total`).
3. Add `delivered`-only status tier if product requires it.
4. Subscribe to `users` INSERT on org screen.
5. Set `AlertTargeting.serverSideEnabled` false until Edge Function exists, or implement filtering.

---

## Feature checklist (final)

| Feature | Status |
|---------|--------|
| Departments CRUD | ✅ Complete |
| Groups CRUD + membership | ✅ Complete |
| Leader targeting UI | ✅ Complete |
| Alert targeting delivery | ❌ Org-wide only |
| Recipient count (UI) | ✅ With stale-data caveat |
| Alert RED/GREEN send | ✅ |
| Alert history | ⚠️ Local only |
| Receipt fan-out on send | ✅ |
| Member ack button | ✅ RED; ✅ GREEN (SnackBar) |
| Leader ack visibility | ⚠️ Details screen only |
| Realtime alerts | ✅ |
| Realtime receipts | ✅ Details screen |
| Realtime users | ⚠️ Perf issue |
| Realtime groups | ❌ Not implemented |

---

## Conclusion

The codebase reflects **significant progress** across organization management, groups, and leader targeting UX. However, **the app is not fully complete** for production alerting:

- **Targeting is write-only** — filters affect DB rows and UI counts but not who receives notifications.
- **Acknowledgement is partially connected** — member RED path works when alert has a DB id; leader recipient path and history integration remain incomplete.
- **Performance risks** on the organization screen likely explain recent **UI freezes/lag** during status updates.

**Recommendation:** Address P0–P1 before adding new features. Do not expand UI until delivery/ack semantics are aligned end-to-end.
