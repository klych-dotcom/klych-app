import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Push-notification scaffolding (Phase 1 preparation — SKELETON ONLY).
///
/// What this does today:
///   * Initializes Firebase core (safe, invisible, guarded).
///
/// What this deliberately does NOT do yet (later phases):
///   * Request OS permission automatically.
///   * Register/refresh device tokens (gated on device_tokens RLS — see
///     rls_architecture_review.md Phase D).
///   * Handle incoming messages, route taps, or display/send any push.
///
/// Nothing here changes existing alert behavior; the in-app Realtime path
/// remains the sole delivery channel until later phases wire push in.
class PushService {
  PushService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Initializes Firebase core. Safe to call once at startup. On any failure
  /// the app degrades gracefully to Realtime-only delivery (no exception
  /// propagates). Returns whether Firebase is available.
  static Future<bool> initializeApp() async {
    if (_initialized) return true;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      debugPrint('PushService: Firebase initialized');
      return true;
    } catch (e) {
      debugPrint('PushService: Firebase init failed (push disabled): $e');
      return false;
    }
  }

  /// Requests OS notification permission. NOT called automatically yet — this is
  /// a building block for the Phase 1 token-registration flow.
  static Future<bool> requestPermission() async {
    if (!_initialized) return false;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final status = settings.authorizationStatus;
      debugPrint('PushService.requestPermission: $status');
      return status == AuthorizationStatus.authorized ||
          status == AuthorizationStatus.provisional;
    } catch (e) {
      debugPrint('PushService.requestPermission failed: $e');
      return false;
    }
  }

  /// Returns the FCM token for this device, or null if unavailable.
  /// On iOS this requires APNs to be configured (capability + .p8 in Firebase);
  /// until then it returns null. Building block only — not auto-invoked.
  static Future<String?> fetchToken() async {
    if (!_initialized) return null;
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('PushService.fetchToken failed: $e');
      return null;
    }
  }

  /// Platform string compatible with device_tokens.platform CHECK constraint.
  static String get platform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      default:
        return 'web';
    }
  }
}
