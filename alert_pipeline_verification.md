# KLYCH — Alert Pipeline Verification (Pre-Push)

**Architecture & correctness audit only. No code/schema/migrations/functions were created or modified.**

Question: *Can a server-side push dispatcher safely use `alert_receipts` as the
source of truth for recipients?*

**Short answer:** `alert_receipts` is the **correct** source of truth, **but the
current creation pipeline is NOT atomic**, so a dispatcher triggered on
`alerts INSERT` would almost always fire **before receipts (or targets) exist**.
This must be fixed before building the dispatcher. Detailed findings below.

---

## 1. Exact alert creation sequence (from code)

Source: `lib/services/alert_service.dart` → `AlertService.createAlert` (lines 18–118).
Each `supabase.from(...).insert()` / `.select()` is an **independent PostgREST
HTTP request**, i.e. its **own implicit auto-committed transaction**. There is no
wrapping DB transaction.

```
# In-memory (client, reads only)
1. fetchOrgUsers(org)                                  [SELECT]            (alert_service.dart:26)
2. fetchGroups(org)                                    [SELECT]            (:27)
3. recipients.resolveRecipients(...) → canSend check   [in memory]         (:29-37)
4. recipients.toTargetSpecs(...) → non-empty check     [in memory]         (:39-46)

# Writes — each its own committed request, in this order
5. INSERT alerts (.select().single())                  [TXN #1, COMMITS]   (:52-62)
   └─► alerts row now EXISTS + VISIBLE (realtime emits, webhook would fire)
6. for each target spec:
     - INSERT alert_targets                            [TXN #2..n]         (:69-72 / :81-84)
     - if 'users': INSERT alert_target_users (one per userId, looped)
                                                        [TXN per user]      (:74-79)
7. resolveRecipientIdsForAlert(alertId)                [SELECTs: targets,
                                                         target_users,
                                                         org users, groups] (:87-92)
8. INSERT alert_receipts (bulk, one request)           [TXN last, COMMITS]  (:98-101)

# On any failure in steps 6–8
9. catch → AlertDeliveryService.deleteAlert(alertId)   [CASCADE delete]     (:102-110)
```

For comparison, the **realtime receive** path (`alert_realtime_listener.dart`,
and the leader/member equivalents) reacts to the **step-5** `alerts` INSERT event,
then calls `shouldUserReceiveAlert` → `hasReceipt` else `resolveRecipientIdsForAlert`.

**Key fact:** the `alerts` row is committed and externally visible at **step 5**,
while `alert_targets`, `alert_target_users`, and `alert_receipts` are written in
**steps 6–8** — multiple later, independent round-trips.

---

## 2. Transactional guarantees

| Question | Finding |
|----------|---------|
| All inserts in a single transaction? | **No.** Every insert is a separate PostgREST request / separate auto-commit. No `rpc`/`BEGIN…COMMIT` wraps the sequence. |
| Can a step succeed while later steps fail? | **Yes.** e.g. `alerts` + some `alert_targets` commit, then the receipts insert fails. Steps are independent commits. |
| Can an alert exist without receipts? | **Yes — transiently always** (between step 5 and step 8), and **permanently** if the client dies mid-sequence or if both the failing step *and* the compensating `deleteAlert` fail. The rollback is best-effort and swallows its own error (`alert_service.dart:104-108`). There is **no server-side cleanup** of orphaned alerts. |
| Can receipts exist without targets? | **Not in practice:** receipts are written last (step 8) and only after `resolveRecipientIdsForAlert` reads targets. **Not DB-enforced**, but the code ordering guarantees targets precede receipts. |
| Can duplicate receipts be created? | **No.** Two layers prevent it: (a) `recipientIds` is built from a `Set` and de-duped (`alert_service.dart:87-92`); (b) DB constraint `alert_receipts_unique UNIQUE (alert_id, user_id)` (`schema.sql:210`). `alert_target_users` is likewise `PRIMARY KEY (alert_id, user_id)` (`schema.sql:194`). |

**Integrity backstop that works well:** all child tables are
`REFERENCES alerts(id) ON DELETE CASCADE` (`schema.sql:166,192,204`), so the
compensating `deleteAlert` (when it succeeds) cleanly removes targets, target_users,
and receipts.

---

## 3. Race condition analysis (webhook on `alerts INSERT`)

**Assume:** `alerts INSERT` → Database Webhook → Edge Function dispatcher that
reads `alert_receipts`.

### Can the webhook fire before targets / target_users / receipts exist?

**YES — and it is the expected case, not an edge case.**

**How:** The webhook fires when the **step-5** `alerts` commit is replicated. At
that instant, steps 6–8 have **not run** — they are subsequent HTTP round-trips
from a mobile client (one per target row, one per explicit user, the resolve
SELECTs, then the receipts insert). The dispatcher reading `alert_receipts` for
that `alert_id` would get **0 rows** and send **nothing**.

**Likelihood:** **Very high / near-certain.** The window spans multiple sequential
client→server round-trips (tens of ms to several seconds on mobile/poor networks),
while webhook dispatch latency is independent and frequently shorter. For a
multi-target alert the window is even larger (looped inserts).

**Second failure mode (false push):** If creation **rolls back** at step 8/9
(e.g. receipts insert fails), the webhook for the now-deleted alert may already
have fired → the dispatcher could push an alert that no longer exists / had no
valid recipients.

**Note — the same latent race already exists in the realtime path:** a recipient
device that processes the step-5 `alerts` event *before* targets/receipts land
will resolve an empty set and **silently skip the alert**. In practice the
recipient's read round-trip usually lets the writes land first, but it is not
guaranteed. The mitigation below fixes both paths.

### Mitigation (recommended, in priority order)

1. **Make alert creation atomic via a single Postgres RPC** (e.g.
   `create_alert(...)` SECURITY DEFINER) that inserts `alerts` + `alert_targets`
   + `alert_target_users` + `alert_receipts` inside **one transaction**.
   Logical replication emits the `alerts` INSERT **only at commit**, by which
   point receipts are committed in the same transaction. The webhook-on-INSERT
   race disappears, the realtime race disappears, orphaned alerts become
   impossible, and the client-side best-effort rollback is no longer needed.
   *(Requires a future migration — out of scope for this audit, but it is the
   clean fix.)*
2. **If you cannot make it atomic yet:** do **not** trigger on `alerts INSERT`.
   Instead trigger the dispatcher on a definitive post-receipts signal — e.g. a
   final `UPDATE alerts SET dispatch_ready = true` written after step 8, with the
   webhook on that UPDATE; or trigger on `alert_receipts` INSERT and group/debounce
   by `alert_id` (receipts are the last step, so existence is guaranteed).
3. **Defensive dispatcher (weakest, only as a stopgap):** retry reading
   `alert_receipts` with bounded backoff and ignore alerts that disappear
   (rolled back). Fragile; do not rely on this alone.

---

## 4. Source of truth recommendation

**Recommended: Option A — `alert_receipts`** (conditioned on the §3 atomicity fix).

| Option | Verdict | Reasoning |
|--------|---------|-----------|
| **A. `alert_receipts`** | ✅ **Recommended** | It is the **frozen, intended-recipient snapshot** computed at send time, with the **sender already excluded** (`alert_service.dart:91`) and **de-duped** by `UNIQUE(alert_id,user_id)`. It is exactly what the in-app flow treats as authoritative (`shouldUserReceiveAlert` checks `hasReceipt` first). Cheap indexed read (`alert_receipts_alert_idx`). Push delivery stays perfectly consistent with in-app delivery + acknowledgement tracking. No logic duplication. |
| B. `alert_targets` + `alert_target_users` | ❌ | Requires re-running resolution server-side (needs an org-users + group-membership snapshot). Can **drift** from receipts if status/membership changed between send and dispatch. Duplicates logic. |
| C. Recompute via resolution logic | ❌ (backstop only) | Same drift problem, most expensive, and requires porting the Dart `resolveFromTargetRows` union logic to TS/SQL. Keep only as a verification backstop. |

**Why "frozen snapshot" matters:** receipts capture *who was targeted at send
time*. Resolving from targets at dispatch time could include/exclude users whose
status or group membership changed in the interim — incorrect for an emergency
that was addressed to a specific set. Receipts are the right semantics.

---

## 5. Consistency with the current realtime flow

Push can be added as a **purely additive** layer. The following **do not need to
change**:

- **Realtime subscriptions** — `alerts` INSERT channels per role remain as-is.
- **RED alert behavior** — fullscreen `AlertScreen` + alarm + vibration unchanged.
- **Acknowledgement flow** — `markAcknowledged` / `markOpened` unchanged.
- **Receipt tracking** — schema and `AlertReceiptService` writes unchanged.

**Required additions / one correctness change:**

1. **(Correctness, prerequisite)** Atomic creation or post-receipts dispatch
   trigger — see §3. This is the only item that touches the existing send path,
   and it hardens the current realtime path too.
2. **(Additive)** Client FCM token registration into `device_tokens`; server
   dispatcher (Edge Function); notification-tap routing. None of this alters
   existing behavior.
3. **(Additive) Foreground de-duplication:** when the app is foregrounded, a user
   may receive *both* the realtime event and the push. The app already de-dupes
   realtime via `AlertDeliveryTracker.tryMarkProcessed`; the push handler must go
   through the **same** dedupe key (`alert_id`) to avoid a double alarm.
4. **(Clarify, not change) `delivered_at` semantics:** today only the foreground
   client sets `delivered_at`. APNs/FCM delivery won't set it unless a background
   data-message handler does. Don't overload `delivered_at` with "pushed"; if you
   need push-delivery telemetry, model it separately later. No change to current
   tracking required.

---

## 6. Production readiness score (pipeline-specific)

### Receipts-based push foundation: **6 / 10 as-is → 9 / 10 after the atomicity fix**

**Strengths**
- Clean service separation; `alert_receipts` is authoritative, sender-excluded, de-duped.
- DB integrity is solid: `UNIQUE(alert_id,user_id)`, `PK(alert_id,user_id)`, full `ON DELETE CASCADE`.
- Deterministic UNION resolution (`resolveFromTargetRows`) reused for delivery, receipts, and history; well-indexed.
- Compensating delete exists and cascades correctly when it runs.

**Blockers**
- **No atomic transaction** across alert/targets/receipts (independent PostgREST commits).
- **`alerts` row is visible before receipts exist** → a webhook/realtime consumer triggered on `alerts INSERT` races the writes (near-certain to read 0 receipts).
- Rollback is **best-effort and self-swallowing**; a failed rollback leaves an **orphan alert with no server cleanup**.

**Risks**
- Client crash / network drop mid-sequence → persistent alert-without-receipts.
- Dispatcher false-positive push for a rolled-back alert.
- Membership/status drift if a dispatcher uses targets recompute (avoided by choosing receipts).

**Recommended next step**
> **Before building the dispatcher, make alert creation atomic** — move the
> `alerts + alert_targets + alert_target_users + alert_receipts` writes into a
> single Postgres `create_alert(...)` RPC (one transaction). Then trigger the push
> dispatcher on the (now race-free) `alerts INSERT` and read **`alert_receipts`**
> as the source of truth. This single change removes every blocker above and also
> hardens the existing realtime delivery path. Until then, do **not** drive a
> receipts-based dispatcher off `alerts INSERT`.

**Verdict:** The pipeline's *shape* and data model are a safe, correct foundation
for FCM/APNs, and `alert_receipts` is the right source of truth — **conditional on
adding atomic creation (or a post-receipts dispatch trigger)**. That is the one
prerequisite that gates safe push implementation.
