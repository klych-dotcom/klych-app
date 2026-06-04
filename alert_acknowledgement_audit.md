# KLYCH Alert Acknowledgement Audit

**Date:** 2026-05-31  
**Scope:** Flutter client + Supabase v2 `alert_receipts` table (schema unchanged)

---

## Executive summary

**`alert_receipts` was schema-ready but not wired in Flutter.** There was no “Підтвердити отримання” button. Members saw **“ЗУПИНИТИ ТРИВОГУ”**, which only stopped audio/vibration — **no database writes**.

Receipt tracking is implemented in this pass (`AlertReceiptService` + member/leader UI). Historical alerts sent before this change will have no receipt rows.

---

## 1. “Підтвердити отримання” — prior behavior

| Step | What happened |
|------|-----------------|
| Member receives RED alert | Realtime `alerts` INSERT → local `SharedPreferences` history → fullscreen `AlertScreen` |
| Member taps button | **“ЗУПИНИТИ ТРИВОГУ”** (not “Підтвердити отримання”) |
| On tap | `player.stop()`, `Vibration.cancel()`, `Navigator.pop()` |
| Database | **Nothing** |

GREEN alerts: SnackBar only — no acknowledgement.

---

## 2. Was data written to `alert_receipts`?

**No** — zero Dart references before this implementation.

---

## 3. Were rows created on alert send?

**No (before fix).** `AlertService.createAlert()` wrote `alerts` + `alert_targets` only. No Edge Function or trigger creates receipts.

---

## 4–6. Timestamp columns (before fix)

| Column | Updated? | Intended owner |
|--------|----------|----------------|
| `delivered_at` | Never | Client on receive (or FCM) |
| `opened_at` | Never | Client when alert UI opens |
| `acknowledged_at` | Never | Client on confirm |

---

## 7. Screens reading acknowledgement data (before fix)

**None.** Leader “ОСТАННІ ОПОВІЩЕННЯ” and member history used **local** `SharedPreferences` only.

---

## Implementation (this pass)

### Lifecycle

```
Alert send → alert_receipts per resolved recipient (exclude sender)
Realtime receive → delivered_at
AlertScreen open → opened_at
“Підтвердити отримання” → acknowledged_at
Leader Alert Details → fetch + realtime UPDATE
```

### Status mapping

| Condition | Display |
|-----------|---------|
| `acknowledged_at` set | ✓ Підтверджено |
| `opened_at` only | ⏳ Очікує |
| else | ❌ Не відкрито |

### Files

| File | Change |
|------|--------|
| `lib/services/alert_receipt_service.dart` | NEW |
| `lib/services/alert_service.dart` | Receipt fan-out |
| `lib/screens/alert_screen.dart` | Ack button + writes |
| `lib/screens/member_home_screen.dart` | delivered + green ack |
| `lib/screens/leader_alert_details_screen.dart` | NEW |
| `lib/screens/leader_home_screen.dart` | Tap → details |

### Verification

```sql
SELECT user_id, delivered_at, opened_at, acknowledged_at
FROM alert_receipts WHERE alert_id = '<id>';
```
