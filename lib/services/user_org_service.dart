import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/user_role.dart';
import '../models/user_status.dart';

import '../utils/department_labels.dart';

class UserOrgService {
  static const userSelect =
      'id, auth_id, callsign, role, organization_id, '
      'department_id, status, is_disabled, created_at, last_activity_at, '
      'departments(id, name)';

  static Future<String?> currentUserId() async {
    final profile = await currentUserProfile();
    return profile?['id']?.toString();
  }

  static Future<Map<String, dynamic>?> currentUserProfile() async {
    final authUser = supabase.auth.currentUser;
    if (authUser == null) return null;

    final row = await supabase
        .from('users')
        .select(userSelect)
        .eq('auth_id', authUser.id)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  static Future<void> touchLastActivity(String userId) async {
    await supabase.from('users').update({
      'last_activity_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  static Future<List<Map<String, dynamic>>> fetchOrgUsers(
    String organizationId, {
    bool includeDisabled = true,
  }) async {
    var query = supabase
        .from('users')
        .select(userSelect)
        .eq('organization_id', organizationId);

    if (!includeDisabled) {
      query = query.eq('is_disabled', false);
    }

    final rows = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> updateCallsign({
    required String userId,
    required String callsign,
  }) async {
    final trimmed = callsign.trim();
    if (trimmed.isEmpty) {
      throw Exception('Позивний не може бути порожнім');
    }

    await supabase.from('users').update({
      'callsign': trimmed,
      'last_activity_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  static Future<void> updateStatus({
    required String userId,
    required String status,
  }) async {
    await supabase.from('users').update({
      'status': UserStatus.normalize(status),
      'last_activity_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', userId);
  }

  static Future<void> updateRole({
    required String userId,
    required String role,
  }) async {
    await supabase.from('users').update(UserRole.toDbFields(role)).eq('id', userId);
  }

  static Future<void> updateDepartment({
    required String userId,
    required String? departmentId,
  }) async {
    await supabase
        .from('users')
        .update({'department_id': departmentId})
        .eq('id', userId);
  }

  static Future<void> setDisabled({
    required String userId,
    required bool disabled,
  }) async {
    await supabase
        .from('users')
        .update({'is_disabled': disabled})
        .eq('id', userId);
  }

  static Future<void> removeUser(String userId) async {
    await supabase.from('users').delete().eq('id', userId);
  }

  static RealtimeChannel subscribeUserChanges({
    required String organizationId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    final channel = supabase.channel('org-users-$organizationId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_id',
            value: organizationId,
          ),
          callback: onChange,
        )
        .subscribe();

    return channel;
  }

  static String departmentName(Map<String, dynamic> user) {
    final dept = user['departments'];
    if (dept is Map) {
      return DepartmentLabels.localize(dept['name']?.toString());
    }
    return '—';
  }

  static Map<String, int> countByStatus(List<Map<String, dynamic>> users) {
    final counts = <String, int>{};
    for (final status in UserStatus.all) {
      counts[status] = 0;
    }
    for (final user in users) {
      if (user['is_disabled'] == true) continue;
      final status = UserStatus.normalize(user['status']?.toString());
      counts[status] = (counts[status] ?? 0) + 1;
    }
    return counts;
  }
}
