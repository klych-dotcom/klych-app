import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// Persists FCM/APNs device tokens to the `device_tokens` table
/// (Phase 1 preparation — SKELETON ONLY).
///
/// IMPORTANT: These writes are NOT wired into login/logout yet. Do NOT invoke
/// them until owner-only RLS is enabled on `device_tokens`
/// (see rls_architecture_review.md §5 + Phase D). Writing tokens to a
/// currently-open table would be a security regression.
///
/// Schema: device_tokens(user_id, token, platform∈{ios,android,web},
/// is_active, updated_at) with UNIQUE(token) and UNIQUE(user_id, token).
class DeviceTokenService {
  DeviceTokenService._();

  static String _nowUtc() => DateTime.now().toUtc().toIso8601String();

  /// Upserts the current device's token for [userId] (one row per user+device).
  static Future<void> upsertToken({
    required String userId,
    required String token,
    required String platform,
  }) async {
    try {
      await supabase.from('device_tokens').upsert(
        {
          'user_id': userId,
          'token': token,
          'platform': platform,
          'is_active': true,
          'updated_at': _nowUtc(),
        },
        onConflict: 'user_id,token',
      );
      debugPrint(
        'DeviceTokenService.upsertToken user=$userId platform=$platform',
      );
    } on PostgrestException catch (e) {
      debugPrint('DeviceTokenService.upsertToken: $e');
      rethrow;
    }
  }

  /// Deactivates a token on logout / when FCM reports it invalid. Deactivation
  /// (not delete) preserves history and matches the dispatcher's cleanup model.
  static Future<void> deactivateToken(String token) async {
    try {
      await supabase
          .from('device_tokens')
          .update({'is_active': false, 'updated_at': _nowUtc()})
          .eq('token', token);
      debugPrint('DeviceTokenService.deactivateToken');
    } on PostgrestException catch (e) {
      debugPrint('DeviceTokenService.deactivateToken: $e');
    }
  }
}
