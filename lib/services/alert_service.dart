import '../main.dart';
import '../models/alert_constants.dart';
import '../models/alert_targeting.dart';

class AlertService {
  /// Inserts an alert using the current production [alerts] schema.
  ///
  /// [target] is reserved for future server-side targeting. It is ignored until
  /// [AlertTargeting.serverSideEnabled] is true and the delivery pipeline persists it.
  /// TODO: Include target in insert when server-side targeting is enabled.
  static Future<Map<String, dynamic>> createAlert({
    required String organizationId,
    required String message,
    required String level,
    required String target,
    required String createdByAuthId,
    required String createdByName,
  }) async {
    assert(
      AlertTargeting.serverSideEnabled || target.isNotEmpty,
      'target is reserved for future server-side delivery',
    );

    final row = await supabase
        .from('alerts')
        .insert({
          'organization_id': organizationId,
          'message': message,
          'type': level,
          'created_by': createdByAuthId,
          'created_by_name': createdByName,
          // TODO: Add 'target': target when AlertTargeting.serverSideEnabled.
        })
        .select()
        .single();

    return Map<String, dynamic>.from(row);
  }

  static String defaultMessage(String level) {
    return level == AlertLevel.green
        ? 'ℹ️ Інформаційне повідомлення'
        : '🚨 ТРИВОГА';
  }
}
