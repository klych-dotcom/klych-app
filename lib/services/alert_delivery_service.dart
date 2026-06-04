import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/alert_target_spec.dart';
import '../models/user_status.dart';
import 'alert_receipt_service.dart';
import 'group_service.dart';
import 'user_org_service.dart';

/// Resolves alert recipients from [alert_targets] / [alert_target_users] (union semantics).
class AlertDeliveryService {
  /// Recipient IDs for a persisted alert — single source of truth for delivery + receipts.
  static Future<Set<String>> resolveRecipientIdsForAlert({
    required String alertId,
    required String organizationId,
  }) async {
    final targets = await _fetchTargets(alertId);
    if (targets.isEmpty) {
      debugPrint('AlertDeliveryService: no targets for alert $alertId');
      return {};
    }

    final explicitUserIds = await _fetchExplicitUserIds(alertId);
    final orgUsers = await UserOrgService.fetchOrgUsers(organizationId);
    final groupMemberIdsByGroup = await GroupService.fetchGroupMemberIdsByGroup(
      organizationId,
    );

    return resolveFromTargetRows(
      targets: targets,
      explicitUserIds: explicitUserIds,
      orgUsers: orgUsers,
      groupMemberIdsByGroup: groupMemberIdsByGroup,
    );
  }

  /// Whether [userId] should receive notification UI for [alert].
  static Future<bool> shouldUserReceiveAlert({
    required Map<String, dynamic> alert,
    required String organizationId,
    required String userId,
  }) async {
    if (alert['organization_id']?.toString() != organizationId.toString()) {
      return false;
    }

    final alertId = alert['id']?.toString();
    if (alertId == null) return false;

    if (await AlertReceiptService.hasReceipt(
      alertId: alertId,
      userId: userId,
    )) {
      return true;
    }

    final recipients = await resolveRecipientIdsForAlert(
      alertId: alertId,
      organizationId: organizationId,
    );
    return recipients.contains(userId);
  }

  /// Org alert history with display metadata (database-backed).
  static Future<List<Map<String, dynamic>>> fetchOrgAlertHistory(
    String organizationId, {
    int limit = 50,
  }) async {
    final rows = await supabase
        .from('alerts')
        .select()
        .eq('organization_id', organizationId)
        .order('created_at', ascending: false)
        .limit(limit);

    final alerts = List<Map<String, dynamic>>.from(rows);
    if (alerts.isEmpty) return alerts;

    final alertIds = alerts
        .map((a) => a['id']?.toString())
        .whereType<String>()
        .toList();

    final ackStats = await AlertReceiptService.fetchAckStatsForAlerts(alertIds);
    final labels = await _buildTargetLabels(alertIds, organizationId);

    return alerts.map((alert) {
      final id = alert['id']?.toString();
      final stats = id != null ? ackStats[id] : null;
      return {
        ...alert,
        'target_label': id != null ? labels[id] ?? 'ОТРИМУВАЧІ (0)' : '—',
        if (stats != null) ...{
          'recipient_count': stats.total,
          'acknowledged_count': stats.confirmed,
        },
      };
    }).toList();
  }

  static Set<String> resolveFromTargetRows({
    required List<Map<String, dynamic>> targets,
    required Set<String> explicitUserIds,
    required List<Map<String, dynamic>> orgUsers,
    required Map<String, Set<String>> groupMemberIdsByGroup,
  }) {
    final hasOrganizationTarget = targets.any(
      (t) => t['target_type']?.toString() == AlertTargetSpec.organization,
    );

    if (hasOrganizationTarget) {
      return orgUsers
          .where((u) => u['is_disabled'] != true)
          .map((u) => u['id']?.toString())
          .whereType<String>()
          .toSet();
    }

    final matched = <String>{};

    for (final user in orgUsers) {
      if (user['is_disabled'] == true) continue;
      final uid = user['id']?.toString();
      if (uid == null) continue;

      if (_userMatchesAnyTarget(
        user: user,
        targets: targets,
        explicitUserIds: explicitUserIds,
        groupMemberIdsByGroup: groupMemberIdsByGroup,
      )) {
        matched.add(uid);
      }
    }

    return matched;
  }

  static bool _userMatchesAnyTarget({
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> targets,
    required Set<String> explicitUserIds,
    required Map<String, Set<String>> groupMemberIdsByGroup,
  }) {
    final uid = user['id']?.toString();
    if (uid == null) return false;

    for (final target in targets) {
      final type = target['target_type']?.toString();
      switch (type) {
        case AlertTargetSpec.organization:
          return true;
        case AlertTargetSpec.department:
          if (user['department_id']?.toString() ==
              target['department_id']?.toString()) {
            return true;
          }
        case AlertTargetSpec.status:
          if (UserStatus.normalize(user['status']?.toString()) ==
              UserStatus.normalize(target['status_code']?.toString())) {
            return true;
          }
        case AlertTargetSpec.group:
          final groupId = target['group_id']?.toString();
          if (groupId != null &&
              (groupMemberIdsByGroup[groupId]?.contains(uid) ?? false)) {
            return true;
          }
        case AlertTargetSpec.users:
          if (explicitUserIds.contains(uid)) return true;
      }
    }
    return false;
  }

  /// Compensating delete — cascades to targets, target_users, receipts.
  static Future<void> deleteAlert(String alertId) async {
    await supabase.from('alerts').delete().eq('id', alertId);
  }

  static Future<List<Map<String, dynamic>>> _fetchTargets(String alertId) async {
    final rows = await supabase
        .from('alert_targets')
        .select()
        .eq('alert_id', alertId);
    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<Set<String>> _fetchExplicitUserIds(String alertId) async {
    final rows = await supabase
        .from('alert_target_users')
        .select('user_id')
        .eq('alert_id', alertId);
    return rows
        .map((r) => r['user_id']?.toString())
        .whereType<String>()
        .toSet();
  }

  static Future<Map<String, String>> _buildTargetLabels(
    List<String> alertIds,
    String organizationId,
  ) async {
    if (alertIds.isEmpty) return {};

    final orgUsers = await UserOrgService.fetchOrgUsers(organizationId);
    final groupMemberIdsByGroup =
        await GroupService.fetchGroupMemberIdsByGroup(organizationId);

    final targetRows = await supabase
        .from('alert_targets')
        .select()
        .inFilter('alert_id', alertIds);

    final explicitRows = await supabase
        .from('alert_target_users')
        .select('alert_id, user_id')
        .inFilter('alert_id', alertIds);

    final targetsByAlert = <String, List<Map<String, dynamic>>>{};
    for (final row in List<Map<String, dynamic>>.from(targetRows)) {
      final alertId = row['alert_id']?.toString();
      if (alertId == null) continue;
      targetsByAlert.putIfAbsent(alertId, () => []).add(row);
    }

    final explicitByAlert = <String, Set<String>>{};
    for (final row in List<Map<String, dynamic>>.from(explicitRows)) {
      final alertId = row['alert_id']?.toString();
      final userId = row['user_id']?.toString();
      if (alertId == null || userId == null) continue;
      explicitByAlert.putIfAbsent(alertId, () => {}).add(userId);
    }

    final labels = <String, String>{};
    for (final alertId in alertIds) {
      final count = resolveFromTargetRows(
        targets: targetsByAlert[alertId] ?? [],
        explicitUserIds: explicitByAlert[alertId] ?? {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: groupMemberIdsByGroup,
      ).length;
      labels[alertId] = 'ОТРИМУВАЧІ ($count)';
    }
    return labels;
  }

  /// Member/admin alert history — alerts where user has a receipt row.
  static Future<List<Map<String, dynamic>>> fetchUserAlertHistory({
    required String userId,
    required String organizationId,
    int limit = 50,
  }) async {
    final rows = await supabase
        .from('alert_receipts')
        .select(
          'delivered_at, opened_at, acknowledged_at, created_at, '
          'alerts(id, organization_id, message, level, sender_user_id, '
          'is_test, created_at)',
        )
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);

    final alerts = <Map<String, dynamic>>[];
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final alertRaw = row['alerts'];
      if (alertRaw is! Map) continue;
      final alert = Map<String, dynamic>.from(alertRaw);
      if (alert['organization_id']?.toString() != organizationId) continue;
      alerts.add({
        ...alert,
        'delivered_at': row['delivered_at'],
        'opened_at': row['opened_at'],
        'acknowledged_at': row['acknowledged_at'],
      });
    }
    return alerts;
  }
}
