# P0 Stabilization Fix Report

## Summary

Fixed all P0 delivery-integrity findings from `klych_stability_audit.md` and addressed P1 performance/subscription issues. No schema changes. Uses existing v2 tables only.

---

## Root Causes

### P0-1 — Alert delivery ignores targeting

**Root cause:** `AlertUtils.shouldReceiveAlert()` only compared `organization_id`, so every org member received every realtime alert regardless of `alert_targets`.

**Fix:** Introduced `AlertDeliveryService` as the single recipient resolver. It reads persisted `alert_targets` + `alert_target_users`, applies union semantics (per schema), and resolves department/status/group/users/organization targets against org users and group membership.

### P0-2 — Receipt vs notification mismatch

**Root cause:** Receipts were created from `AlertRecipientsSelection.resolveDeliveryUserIds()` at send time, but notifications used the org-wide `shouldReceiveAlert()` check — two different recipient sets.

**Fix:** 
- Receipt creation now uses `AlertDeliveryService.resolveRecipientIdsForAlert()` **after** targets are persisted (same resolver as delivery).
- Notification gating uses `AlertDeliveryService.shouldUserReceiveAlert()` which checks receipt row first, then target resolution fallback.
- Removed `_ensureRow()` orphan receipt inserts in `AlertReceiptService` — receipts only exist for intended recipients.

### P0-3 — Non-atomic alert creation

**Root cause:** Alert row, targets, and receipts were written sequentially with no rollback. Receipt failure left alert + targets without receipts.

**Fix:** Wrapped target + receipt writes in try/catch. On failure, `AlertDeliveryService.deleteAlert(alertId)` runs compensating delete (CASCADE removes targets, target_users, receipts). Documented in `AlertService.createAlert()`.

### P0-4 — Leader acknowledgement visibility

**Root cause:** Leader alert history was SharedPreferences-only (`leader_alerts_history`). Acknowledgements were stored in `alert_receipts` but the list did not reflect DB state.

**Fix:** Leader home loads history via `AlertDeliveryService.fetchOrgAlertHistory()` (database-backed). List shows recipient count and ack count (`✓ N/M`). Tap opens `LeaderAlertDetailsScreen` with full receipt list + timestamps (already DB-backed; unchanged logic, now reachable from live history).

---

## Files Modified

| File | Change |
|------|--------|
| `lib/services/alert_delivery_service.dart` | **New** — recipient resolution, delivery check, org history, compensating delete |
| `lib/services/alert_service.dart` | DB-backed receipt fan-out; compensating rollback on failure |
| `lib/services/alert_receipt_service.dart` | `hasReceipt`, ack stats helpers; no orphan receipt inserts |
| `lib/services/group_service.dart` | Batch group member fetch; `fetchGroupMemberIdsByGroup()` |
| `lib/screens/member_home_screen.dart` | Target-aware delivery via `AlertDeliveryService` |
| `lib/screens/leader_home_screen.dart` | DB history, target-aware delivery, markDelivered, green ack |
| `lib/screens/leader_org_screen.dart` | Patch single user on realtime UPDATE (no full reload) |
| `lib/screens/leader_alert_details_screen.dart` | Debounced receipt reload on realtime |
| `lib/utils/alert_utils.dart` | Deprecated org-only `shouldReceiveAlert()` |
| `test/alert_delivery_service_test.dart` | **New** — unit tests for target resolution |

---

## Delivery Integrity Verification

### Single source of truth flow

```
AlertService.createAlert()
  → insert alerts
  → insert alert_targets (+ alert_target_users for explicit users)
  → AlertDeliveryService.resolveRecipientIdsForAlert()  ← reads back persisted targets
  → AlertReceiptService.createReceiptsForAlert()

Member/Leader realtime handler
  → (Leader only) refresh org alert history from DB
  → AlertDeliveryService.shouldUserReceiveAlert()
      1. receipt row exists? → deliver notification
      2. else resolve from alert_targets → deliver if matched
  → AlertReceiptService.markDelivered() (only if receipt exists)
```

### Target types verified (unit tests + resolver logic)

| Target type | Behavior |
|-------------|----------|
| Organization | All non-disabled org users |
| Department | Users with matching `department_id` |
| Status | Users with matching `status` |
| Group | Users in `group_members` for target group |
| Users | Explicit IDs in `alert_target_users` |
| Multi-row | Union across rows (schema semantics) |

### Intersection at send vs union at read

When leader selects multiple filter categories, `AlertRecipientsSelection.toTargetSpecs()` stores a single `users` target with resolved IDs (intersection at compose time). Single-category sends store native target rows (department/status/group). Delivery resolver handles both correctly.

---

## Performance Improvements (P1)

### P1-1 — LeaderOrgScreen

**Before:** Every user realtime UPDATE triggered full `_load()` — users + departments + N+1 group member queries.

**After:**
- Realtime handler patches the changed user row in memory (one SELECT).
- `GroupService.fetchGroups()` uses one batch query for all group members via `inFilter('group_id', ...)`.

### P1-2 — Realtime subscription audit

| Screen | Subscription | Disposal | Duplicate handling |
|--------|-------------|----------|-------------------|
| Member home | `member-alerts-{orgId}` | `channel?.unsubscribe()` in dispose | `AlertDeliveryTracker.tryMarkProcessed()` |
| Leader home | `leader-alerts-{orgId}` | `channel?.unsubscribe()` in dispose | `AlertDeliveryTracker.tryMarkProcessed()` |
| Leader org | `org-users-{orgId}` | `_usersChannel?.unsubscribe()` in dispose | Single-user patch (no duplicate reload) |
| Alert details | `alert-receipts-{alertId}` | `_channel?.unsubscribe()` + timer cancel | 300ms debounced reload |

No duplicate subscriptions found — each screen unsubscribes before resubscribe in `subscribeAlerts()`.

---

## Acknowledgement Verification

Path: **Alert → Receipts → Acknowledgements → Leader visibility**

1. **Create:** `AlertReceiptService.createReceiptsForAlert()` — one row per resolved recipient.
2. **Deliver:** `markDelivered()` sets `delivered_at` (only existing receipts).
3. **Open/Ack:** Member/leader green SnackBar or red `AlertScreen` → `markOpened()` / `markAcknowledged()`.
4. **Leader list:** `fetchOrgAlertHistory()` includes `recipient_count` + `acknowledged_count`.
5. **Leader details:** `LeaderAlertDetailsScreen` shows per-recipient status + delivered/opened/acknowledged timestamps from DB with realtime updates.

SharedPreferences leader history removed — leader data is database-backed.

---

## P0-3 Consistency Approach (Documented)

Supabase client cannot run multi-table transactions from Flutter without an RPC. Chosen approach:

1. Insert alert (minimal row).
2. Insert targets + receipts in try block.
3. On any failure → `DELETE FROM alerts WHERE id = ?` (FK CASCADE cleans dependents).

This prevents orphaned alerts without schema changes.

---

## Test Results

```bash
flutter analyze
flutter test
```

Unit tests cover department, status, group, explicit user, organization, and union targeting in `test/alert_delivery_service_test.dart`.

---

## Manual Verification Checklist

1. Department alert → only department members notified and receipted.
2. Status alert → only matching-status users notified and receipted.
3. Group alert → only group members notified and receipted.
4. User-target alert → only selected users notified and receipted.
5. Leader opens alert → sees recipient list with ack/pending + timestamps.
6. Organization screen → no lag on user status updates (single-user patch).
