import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/alert_exceptions.dart';
import '../models/alert_constants.dart';
import '../models/alert_recipients_selection.dart';

class AlertService {
  /// Creates the alert, its targets, target-users and receipts atomically via a
  /// single transactional Postgres function (`create_alert`). The whole write is
  /// one transaction: any failure (including zero recipients) rolls everything
  /// back server-side, so no orphan alert can exist without receipts.
  static Future<Map<String, dynamic>> createAlert({
    required String organizationId,
    required String message,
    required String level,
    required AlertRecipientsSelection recipients,
    required String senderUserId,
    bool isTest = false,
  }) async {
    try {
      final result = await supabase.rpc('create_alert', params: {
        'p_organization_id': organizationId,
        'p_message': message,
        'p_level': level,
        'p_sender_user_id': senderUserId,
        'p_is_test': isTest,
        'p_org_wide': recipients.orgWide,
        'p_status_codes': recipients.statusCodes.toList(),
        'p_department_ids': recipients.departmentIds.toList(),
        'p_group_ids': recipients.groupIds.toList(),
        'p_user_ids': recipients.userIds.toList(),
      });

      final rows = result as List<dynamic>;
      if (rows.isEmpty) {
        throw NoRecipientsException();
      }

      final row = Map<String, dynamic>.from(rows.first as Map);
      final count = (row['recipient_count'] as num?)?.toInt() ?? 0;

      return {
        ...row,
        'recipient_count': count,
        'target_label': recipients.recipientsLabel(count: count),
      };
    } on PostgrestException catch (e) {
      if (e.message.contains('NO_RECIPIENTS')) {
        throw NoRecipientsException();
      }
      rethrow;
    }
  }

  static String defaultMessage(String level) {
    return level == AlertLevel.green
        ? 'ℹ️ Інформаційне повідомлення'
        : '🚨 ТРИВОГА';
  }
}
