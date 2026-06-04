# KLYCH v2 Hotfix Audit — Phase 3

**Date:** 2026-05-31  
**Scope:** BUG-001 through BUG-004 (live testing fixes)  
**Database:** No schema changes

---

## Summary

| Bug | Root cause | Status |
|-----|------------|--------|
| BUG-001 | No unarchive API or UI; archived rows easy to miss | **Fixed** |
| BUG-002 | Duplicate name UNIQUE violation + silent error swallowing | **Fixed** |
| BUG-003 | Raw `AuthException` passed to SnackBar | **Fixed** |
| BUG-004 | No deep links; Supabase Site URL not app-aware | **Documented** (Dashboard config) |

---

## BUG-001 — Archived department cannot be restored

### Root cause

1. `DepartmentService` had `archive()` but **no `restore()` / `unarchive()`** method.
2. `departments_screen.dart` showed archived rows with a static `ARCHIVED` label only — **no restore action**.
3. Archived departments are excluded from `fetchActive()` (invite join, dropdowns), so they effectively **disappear from operational use** with no way back.

### Fixes implemented

- Added `DepartmentService.restore(departmentId)` — sets `is_archived = false`.
- UI split into **АКТИВНІ** and **АРХІВ** sections.
- App bar toggle to show/hide archive section (default: visible).
- Restore button (`unarchive` icon) on each archived department.
- Success/error SnackBars on archive and restore.

---

## BUG-002 — Department creation fails

### Root cause

1. **Primary:** v2 constraint `UNIQUE (organization_id, name)`. Creating `"Headquarters"` (or any seeded name) fails because `seed_org_departments()` already inserted it. PostgREST returns `23505 duplicate key`.
2. **Secondary:** `_createDepartment()` had **no try/catch** — insert exceptions were unhandled; dialog closed but list never refreshed and **no user-visible error**.
3. Insert payload and column names were **correct** (`organization_id`, `name`); `organization_id` was set properly.

### Fixes implemented

- `DepartmentService.create()` now:
  - Checks for existing row by name within org.
  - If **archived** duplicate → **auto-restores** instead of failing.
  - If **active** duplicate → throws Ukrainian message: `Підрозділ «…» вже існує`.
- `findByName()` helper for pre-insert lookup.
- `rename()` validates duplicate names before update.
- `departments_screen.dart`: try/catch on create/rename/archive/restore with SnackBar errors via `DbErrorMessages`.
- List refresh after every successful mutation.

---

## BUG-003 — Auth errors not user-friendly

### Root cause

Login, registration, and invite join used `e.toString()` or raw `AuthApiException` text in SnackBars.

### Fixes implemented

- New `lib/utils/auth_error_messages.dart` — maps common Supabase auth codes/messages to Ukrainian:
  - `over_email_send_rate_limit` → Забагато листів підтвердження…
  - `invalid_credentials` → Невірний email або пароль.
  - `email_not_confirmed` → Підтвердіть email перед входом.
  - Plus: `user_already_registered`, `weak_password`, network errors, etc.
- Applied in:
  - `login_screen.dart`
  - `create_server_screen.dart`
  - `invite_join_screen.dart` (invite validation errors stay as-is; auth/DB errors mapped)

- New `lib/utils/db_error_messages.dart` for department PostgREST errors (duplicate key).

---

## BUG-004 — Email confirmation link investigation

### Root cause (not a Flutter bug — configuration gap)

KLYCH is a **native mobile app** with **no deep link / URL scheme** configured. Supabase confirmation emails contain a link built from **Dashboard Auth settings**, which by default points to:

- **Site URL:** `http://localhost:3000` (or project default)
- **Redirect:** web URL, not the mobile app

When the user taps the link:

1. Browser opens localhost or an invalid redirect → **link appears broken**.
2. Flutter app never receives the auth callback — **no intent-filter (Android)** or **CFBundleURLTypes (iOS)** exists.
3. `Supabase.initialize()` in `main.dart` does **not** configure `authCallbackUrlHostname` or session detection from incoming links.
4. `supabase_flutter` PKCE flow for mobile requires explicit redirect URL registration.

### Current Flutter assumptions

| Item | Current state |
|------|---------------|
| Deep link handling | **None** — `AndroidManifest.xml` has only LAUNCHER intent |
| iOS URL scheme | **None** — `Info.plist` has no `CFBundleURLTypes` |
| Auth callback in `main.dart` | Standard init only; no `detectSessionInUri` |
| Email confirm required | Depends on Supabase Dashboard (likely **enabled** for admin email signup) |

### What to configure in Supabase Dashboard

**Authentication → URL Configuration**

1. **Site URL** — set to your production web fallback or a hosted redirect page, e.g.  
   `https://your-domain.com/auth/callback`  
   (Not `localhost` for real users.)

2. **Redirect URLs** — add all allowed callbacks, e.g.:
   ```
   io.supabase.klych://login-callback/
   com.klych.app://login-callback/
   http://localhost:3000/**
   ```
   Match exactly what the mobile app will register.

**Authentication → Providers → Email**

3. For **internal / field deployment** (recommended short-term):  
   **Disable “Confirm email”** so admin registration works immediately without link.

4. For **production with confirmation**: enable confirm email **and** implement mobile deep links (below).

### What to add in Flutter (future — not in this hotfix)

1. **Android** `AndroidManifest.xml` — intent-filter with custom scheme:
   ```xml
   <intent-filter>
     <action android:name="android.intent.action.VIEW"/>
     <category android:name="android.intent.category.DEFAULT"/>
     <category android:name="android.intent.category.BROWSABLE"/>
     <data android:scheme="io.supabase.klych" android:host="login-callback"/>
   </intent-filter>
   ```

2. **iOS** `Info.plist` — `CFBundleURLTypes` with same scheme.

3. **`main.dart`** — pass auth options if using deep links:
   ```dart
   await Supabase.initialize(
     url: '...',
     anonKey: '...',
     authOptions: const FlutterAuthClientOptions(
       authFlowType: AuthFlowType.pkce,
     ),
   );
   ```

4. Handle incoming links via `supabase.auth.onAuthStateChange` or `getSessionFromUrl()`.

### Recommended path for KLYCH MVP

**Option A (fastest):** Supabase Dashboard → disable email confirmation for admin signup. Users sign in immediately after `signUp`.

**Option B (production):** Custom URL scheme + redirect URLs + deep link handling in Flutter.

**Option C:** Use real email login only after confirmation via a simple web landing page that shows “Return to app” once verified.

---

## Files modified

| File | Change |
|------|--------|
| `lib/services/department_service.dart` | `restore()`, `findByName()`, smart `create()`, duplicate-safe `rename()` |
| `lib/screens/departments_screen.dart` | Archive/restore UI, sections, error handling, refresh |
| `lib/utils/auth_error_messages.dart` | **New** — Ukrainian auth error mapping |
| `lib/utils/db_error_messages.dart` | **New** — PostgREST error mapping |
| `lib/screens/login_screen.dart` | Use `AuthErrorMessages` |
| `lib/screens/create_server_screen.dart` | Use `AuthErrorMessages` |
| `lib/screens/invite_join_screen.dart` | Use `AuthErrorMessages` for auth errors |

**Not modified:** `main.dart` credentials, `supabase/v2/*.sql`

---

## Manual testing checklist

### BUG-001 — Archive / restore

- [ ] Open **Підрозділи** → archive **Medics** → appears under **АРХІВ**
- [ ] Tap restore (unarchive icon) → **Medics** moves to **АКТИВНІ**
- [ ] Medics appears again in member invite department dropdown
- [ ] Toggle archive visibility (app bar icon) hides/shows **АРХІВ** section

### BUG-002 — Department creation

- [ ] Create department **Evacuation** (new name) → success SnackBar → appears in list
- [ ] Create **Headquarters** (existing active) → error: «вже існує» — no silent failure
- [ ] Archive **Medics**, then create **Medics** again → restores archived row (not duplicate error)
- [ ] Rename department to existing name → clear error message
- [ ] Load errors (airplane mode) → user-visible message, not silent

### BUG-003 — Auth messages

- [ ] Wrong password on login → «Невірний email або пароль.» (not raw AuthApiException)
- [ ] Rapid repeated signups → rate limit message in Ukrainian
- [ ] Unconfirmed email login (if confirm enabled) → «Підтвердіть email перед входом.»

### BUG-004 — Email confirmation

- [ ] Document team decision: disable confirm email **OR** configure redirect URLs + deep links
- [ ] After disabling confirm: admin **Create Server** → immediate access to HomeScreen
- [ ] If confirm enabled: verify Site URL is not `localhost` for production testers

---

## Verification

```bash
flutter analyze lib/   # no errors (info deprecations only)
flutter test           # smoke test passes
```
