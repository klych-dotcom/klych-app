import 'package:flutter/foundation.dart';

import '../main.dart';
import '../models/alert_exceptions.dart';
import '../models/alert_constants.dart';
import '../models/alert_target_spec.dart';
import '../models/alert_recipients_selection.dart';
import '../models/alert_targeting.dart';
import '../services/alert_delivery_service.dart';
import '../services/recipient_resolver.dart';
import '../services/group_service.dart';
import '../services/user_org_service.dart';
import '../services/alert_receipt_service.dart';

class AlertService {
  /// Creates alert + targets + receipts. On failure after alert insert, deletes
  /// the alert row (CASCADE removes targets, target_users, receipts).
  static Future<Map<String, dynamic>> createAlert({
    required String organizationId,
    required String message,
    required String level,
    required AlertRecipientsSelection recipients,
    required String senderUserId,
    bool isTest = false,
  }) async {
    final orgUsers = await UserOrgService.fetchOrgUsers(organizationId);
    final orgGroups = await GroupService.fetchGroups(organizationId);

    final resolved = recipients.resolveRecipients(
      users: orgUsers,
      groups: orgGroups,
      excludeUserId: senderUserId,
    );

    if (!resolved.canSend) {
      throw NoRecipientsException();
    }

    final targets = recipients.toTargetSpecs(
      users: orgUsers,
      groups: orgGroups,
    );

    if (targets.isEmpty) {
      throw NoRecipientsException();
    }
    assert(
      AlertTargeting.serverSideEnabled || targets.isNotEmpty,
      'recipients required',
    );

    final alertRow = await supabase
        .from('alerts')
        .insert({
          'organization_id': organizationId,
          'message': message,
          'level': level,
          'sender_user_id': senderUserId,
          'is_test': isTest,
        })
        .select()
        .single();

    final alertId = alertRow['id'].toString();

    try {
      for (final target in targets) {
        if (target.type == AlertTargetSpec.users) {
          await supabase.from('alert_targets').insert({
            'alert_id': alertId,
            'target_type': AlertTargetSpec.users,
          });

          for (final userId in target.userIds) {
            await supabase.from('alert_target_users').insert({
              'alert_id': alertId,
              'user_id': userId,
            });
          }
        } else {
          await supabase.from('alert_targets').insert(
            target.toAlertTargetRow(alertId),
          );
        }
      }

      final recipientIds = (await AlertDeliveryService.resolveRecipientIdsForAlert(
        alertId: alertId,
        organizationId: organizationId,
      ))
          .where((id) => id != senderUserId)
          .toList();

      if (recipientIds.isEmpty) {
        throw NoRecipientsException();
      }

      await AlertReceiptService.createReceiptsForAlert(
        alertId: alertId,
        userIds: recipientIds,
      );
    } catch (e, st) {
      debugPrint('AlertService.createAlert rollback alert=$alertId: $e\n$st');
      try {
        await AlertDeliveryService.deleteAlert(alertId);
      } catch (rollbackError) {
        debugPrint('AlertService.createAlert rollback failed: $rollbackError');
      }
      rethrow;
    }

    final label = recipients.recipientsLabel(count: resolved.count);

    return {
      ...Map<String, dynamic>.from(alertRow),
      'target_label': label,
    };
  }

  static String defaultMessage(String level) {
    return level == AlertLevel.green
        ? 'ℹ️ Інформаційне повідомлення'
        : '🚨 ТРИВОГА';
  }
}
