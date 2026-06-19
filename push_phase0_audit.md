# KLYCH — Push Notifications Phase 0: Readiness Audit & Preparation

**Scope:** Phase 0 readiness audit + only the clearly-required, zero-risk in-repo
prerequisite. **No push delivery, no Edge Functions, no alert-logic changes, no
runtime Firebase wiring** were implemented.

Builds on `push_notifications_architecture_review.md` and
`rls_architecture_review.md`. Verified against the actual native/config files
(paths cited inline).

---

## 0. What was changed in this pass (only this)

| Change | File | Why it's Phase 0 + safe |
|--------|------|--------------------------|
| Added `POST_NOTIFICATIONS` permission | `android/app/src/main/AndroidManifest.xml` | Mandatory for Android 13+ to ever show a notification; declaring it is inert (no runtime request, no behavior change, no build risk). |

Everything else below is **documented as exact steps, not applied**, because each
remaining item requires a paired **Firebase console / Apple Developer / Xcode**
action (applying only the repo half would break builds), and the app build is
currently live (`flutter run`). They are listed with precise instructions for the
Phase 1 pass.

---

## 1. Firebase audit

**Firebase project:** `alert-app-0700` (project number `783119002746`). One
project, two platform apps registered.

| Item | State | Evidence |
|------|-------|----------|
| `firebase_core` dependency | ✅ `^3.15.2` | `pubspec.yaml:18` |
| `firebase_messaging` dependency | ✅ `^15.2.10` | `pubspec.yaml:19` |
| `firebase_options.dart` (FlutterFire) | ✅ Android + iOS generated | `lib/firebase_options.dart:52-67` |
| Android `google-services.json` | ✅ present, pkg `com.example.alert_app` | `android/app/google-services.json:12` |
| iOS `GoogleService-Info.plist` | ✅ present, bundle `com.klych.app` | `ios/Runner/GoogleService-Info.plist:11-12` |
| **`Firebase.initializeApp(...)`** | ❌ **never called** | `lib/main.dart:13-26` (no Firebase import/init) |
| Android `com.google.gms.google-services` Gradle plugin | ❌ not applied | `android/settings.gradle.kts:20-24`, `android/app/build.gradle.kts:1-6` |

### Identifiers — clarification (corrects earlier "M9 blocker" framing)
- **Android** `applicationId`/`namespace` = `com.example.alert_app`
  (`build.gradle.kts:9,24`) — **matches** its Firebase registration
  (`google-services.json` package_name).
- **iOS** `PRODUCT_BUNDLE_IDENTIFIER` = `com.klych.app`
  (`project.pbxproj:508,694,720`) — **matches** `GoogleService-Info.plist` +
  `firebase_options.dart:66`.

⇒ The two platforms use **different** bundle ids, but **each is correctly
registered in Firebase**, so FCM is functional on both **as-is**. This is a
**product-consistency** issue, not a push blocker. **Recommendation:** do **not**
rename for the MVP (renaming Android to `com.klych.app` would invalidate the
current `google-services.json` and break the build until a new Android app is
registered and the file re-downloaded). Defer unification to a deliberate later
task.

### Missing / conflicts
- **M-A (blocker, Phase 1):** `Firebase.initializeApp` not called → no FCM at all yet.
- **M-B (Android, recommended):** `google-services` Gradle plugin not applied (see §3).
- **No conflicts** between configs and registrations were found.

---

## 2. iOS push readiness (APNs)

| Requirement | State | Evidence / Action |
|-------------|-------|-------------------|
| `UIBackgroundModes` → `remote-notification` | ✅ present | `ios/Runner/Info.plist:52-55` |
| Bundle id matches Firebase iOS app | ✅ `com.klych.app` | `project.pbxproj`, `GoogleService-Info.plist` |
| **`Runner.entitlements` with `aps-environment`** | ❌ **absent** | no `*.entitlements` file exists; no `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj` |
| **Push Notifications capability** (Xcode) | ❌ not enabled | no `com.apple.Push` / SystemCapabilities entry |
| **APNs Auth Key (.p8)** uploaded to Firebase | ❌ unknown/absent | Firebase Console → Project Settings → Cloud Messaging |
| App ID has Push enabled (Apple Developer) | ❌ to confirm | developer.apple.com |
| Provisioning profile incl. Push | ❌ to confirm | regenerate after enabling Push |

### Exact missing steps (do in Phase 1, in Xcode/console — not auto-applied)
1. Xcode → Runner target → **Signing & Capabilities → + Push Notifications**
   (creates `Runner.entitlements` with `aps-environment` and wires
   `CODE_SIGN_ENTITLEMENTS`). *Hand-editing `project.pbxproj` is avoided here to
   prevent project corruption.*
2. Apple Developer → App ID `com.klych.app` → enable **Push Notifications**;
   regenerate provisioning profiles.
3. Create an **APNs Auth Key (.p8)** (Keys section) and **upload it to Firebase**
   (Project Settings → Cloud Messaging → APNs Authentication Key) with Key ID +
   Team ID.
4. (Phase 3, optional) request **Critical Alerts** entitlement from Apple (long
   lead time) for mute/DND bypass; otherwise use Time-Sensitive.

> iOS push **cannot be tested on Simulator** — needs a real device + signed build
> (TestFlight) once the above are done.

---

## 3. Android push readiness

| Requirement | State | Evidence / Action |
|-------------|-------|-------------------|
| `POST_NOTIFICATIONS` permission (API 33+) | ✅ **added this pass** | `AndroidManifest.xml` |
| `google-services` Gradle plugin | ❌ not applied | `settings.gradle.kts`, `app/build.gradle.kts` |
| `google-services.json` | ✅ present | `android/app/google-services.json` |
| High-importance notification channel(s) | ❌ none | needs `flutter_local_notifications` + channel creation (Phase 3) |
| Custom alarm sound resource (`res/raw`) | ❌ none | add `alarm` raw resource for RED channel (Phase 3) |
| Default FCM notification icon/color meta-data | ❌ none | optional manifest meta-data (Phase 3) |
| `MainActivity` launchMode | ✅ `singleTop` | `AndroidManifest.xml:9` (good for tap-routing) |

### Exact missing steps (Phase 1/3)
1. **(Phase 1, recommended) apply `google-services` plugin** — not auto-applied
   here to avoid build risk on the live session:
   - `android/settings.gradle.kts` plugins block:
     `id("com.google.gms.google-services") version "4.4.2" apply false`
   - `android/app/build.gradle.kts` plugins block:
     `id("com.google.gms.google-services")`
   *(Note: `firebase_messaging` can obtain a token via `firebase_options.dart`
   even without this plugin, but applying it is the standard, most robust FCM
   setup and is required if other Firebase SDKs are added.)*
2. **(Phase 3)** add `flutter_local_notifications`; create `klych_red`
   (high-importance, custom sound, full-screen intent) and `klych_info` channels;
   add the `alarm` raw sound; request runtime permission on Android 13+.

---

## 4. Device-token design (review only — no implementation)

Schema is ready: `device_tokens(user_id, token, platform∈{ios,android,web},
is_active, updated_at)` with `UNIQUE(token)` and `UNIQUE(user_id, token)`
(`schema.sql:267-280`).

| Aspect | Design |
|--------|--------|
| **Registration** | After login + permission grant: (iOS) await `getAPNSToken()` then `getToken()`; upsert `{user_id=me, token, platform, is_active=true}` on conflict `(user_id, token)`. |
| **Refresh** | `onTokenRefresh` → upsert same row; rely on the unique constraints. |
| **Logout** | In all 3 logout handlers (`home_screen.dart:258`, `leader_home_screen.dart:454`, `member_home_screen.dart:387`): set this device's token `is_active=false` **and** `FirebaseMessaging.deleteToken()`. |
| **Reassignment** | `UNIQUE(token)` is global → upsert transfers ownership if a device re-registers under another user; dispatcher's `is_active` + org filter prevents stale targeting. |
| **Stale tokens** | Dispatcher deactivates on FCM `UNREGISTERED`/`INVALID_ARGUMENT`; periodic cleanup of long-inactive rows. |
| **Security (gate)** | Enable **owner-only RLS** on `device_tokens` (`user_id = auth_user_id()`, all verbs) **before** writing any token (per `rls_architecture_review.md` §5/Phase D). Dispatcher reads via `service_role`. |

No `device_tokens` code exists yet (`DeviceTokenService`/`PushService` are new in
Phase 1).

---

## 5. Push implementation plan (exact order, post-Phase 0)

| Phase | Work | Touches | Complexity | Risk | Effort |
|-------|------|---------|-----------|------|--------|
| **P0 (this)** | `POST_NOTIFICATIONS` added; audit complete | manifest | Low | None | done |
| **P1 — Token registration** | `Firebase.initializeApp(options:)` in `main.dart`; `PushService` (permission, APNs→FCM token, upsert) + `DeviceTokenService`; logout deactivation; Android `google-services` plugin; **owner-only RLS on `device_tokens`** first | `main.dart`, new services, 3 logout handlers, Gradle, Supabase RLS | Med | Med (iOS certs/RLS gate) | ~3–5 d |
| **P2 — Webhook + Edge Function** | DB Webhook on `alerts INSERT` (secret) → `dispatch_alert` (idempotency claim, read `alert_receipts ⋈ device_tokens ⋈ users` org-filtered); **needs additive `alerts.push_dispatched_at`** (idempotency) | Supabase function + 1 additive migration | Med | Med | ~3–4 d |
| **P3 — FCM/APNs delivery** | FCM HTTP v1 (service-account secret); per-platform payload (Android channel/sound/full-screen intent; APNs priority/interruption-level); invalid-token deactivation | Edge Function, `flutter_local_notifications`, Android channels/sound | Med–High | Med | ~3–5 d |
| **P4 — Realtime+Push dedup & routing** | Process-wide `AlertDeliveryTracker` singleton so foreground push + Realtime never double-fire; global `navigatorKey`; `getInitialMessage`/`onMessageOpenedApp`/`onMessage`/`onBackgroundMessage` → fetch `alert_id` → `AlertScreen` (auth/org-guarded); best-effort `delivered_at` | `main.dart`, mixin, nav | Med | Med | ~3–4 d |
| **P5 — Locked-screen validation** | Real-device matrix (fg/bg/locked/killed) × target types; verify count = `alert_receipts`, no cross-org, single alarm, ack writes; iOS via TestFlight | none (test) | Med | Med (device/cert) | ~2–4 d |

**Total to production RED push (P1–P5): ~2–3 weeks**, dominated by platform/cert
config and the dispatcher — not app rewrites (the atomic RPC already removed the
hardest correctness risk).

---

## 6. Readiness assessment

| Layer | State | Note |
|-------|-------|------|
| Data model (`device_tokens`, alerts, receipts) | ✅ Ready | atomic RPC makes receipts authoritative |
| Dependencies (`firebase_core`, `firebase_messaging`) | ✅ Ready | present |
| Native configs (json/plist/options) | ✅ Ready | each platform correctly registered |
| iOS background mode | ✅ Ready | `remote-notification` present |
| Android notif permission | ✅ Ready (this pass) | `POST_NOTIFICATIONS` added |
| `Firebase.initializeApp` | ❌ Missing | Phase 1 |
| iOS entitlements/capability/APNs key | ❌ Missing | Phase 1 (Xcode/Apple/Firebase console) |
| Android `google-services` plugin | ❌ Missing | Phase 1 (recommended) |
| `device_tokens` RLS | ❌ Missing | **hard gate** before token writes |
| Server dispatcher / webhook | ❌ Missing | Phase 2 |

### Missing prerequisites (must complete before Phase 1 token writes)
1. **Owner-only RLS on `device_tokens`** (security gate).
2. iOS: Push capability + entitlements + **APNs .p8 uploaded to Firebase**.
3. `Firebase.initializeApp` + (recommended) Android `google-services` plugin.

### Risks
- **R1 (Med):** iOS cert/provisioning friction (entitlements, APNs key) — longest lead time.
- **R2 (Med):** enabling `device_tokens` RLS without the owner policy → blocks token writes; sequence RLS-then-writes carefully.
- **R3 (Low–Med):** adding `google-services` Gradle plugin can surface version
  conflicts; apply on a branch and verify a clean build.
- **R4 (Low):** bundle-id divergence (Android vs iOS) — fine for MVP; only revisit
  intentionally with a Firebase re-registration.
- **R5 (Low):** iOS push untestable on Simulator → plan TestFlight early.

---

## Final recommendation

**Phase 0 is essentially complete and KLYCH is ready to begin Phase 1.** The only
in-repo code change required at this stage (`POST_NOTIFICATIONS`) is applied; all
remaining prerequisites are **console/Xcode actions paired with small repo edits**
that should be done together at the start of Phase 1 to avoid broken builds. Begin
Phase 1 with the **`device_tokens` RLS gate first**, then `Firebase.initializeApp`
+ `PushService`/`DeviceTokenService`, then proceed P2→P5 in order.

*No push delivery, Edge Functions, or alert-logic changes were implemented.*
