import '../models/alert_constants.dart';
import '../models/alert_targeting.dart';

class AlertUtils {
  static String? resolveLevel(Map<String, dynamic> alert) {
    return alert['level']?.toString() ?? alert['type']?.toString();
  }

  static bool isRedAlert(String? level) {
    final normalized = level?.trim().toUpperCase();
    return normalized == AlertLevel.red ||
        normalized == 'GENERAL' ||
        normalized == 'TEST';
  }

  static bool isGreenAlert(String? level) {
    return level?.trim().toUpperCase() == AlertLevel.green;
  }

  static String levelLabel(String? level) {
    if (isGreenAlert(level)) return AlertLevel.green;
    if (isRedAlert(level)) return AlertLevel.red;
    return level?.toUpperCase() ?? AlertLevel.red;
  }

  static String levelLabelFromAlert(Map<String, dynamic> alert) {
    return levelLabel(resolveLevel(alert));
  }

  /// Label for display — reflects persisted target only when server targeting is on.
  static String targetLabel(String? storedTarget) {
    if (!AlertTargeting.serverSideEnabled) {
      return AlertTarget.labels[AlertTarget.organization]!;
    }

    return AlertTarget.labels[storedTarget ?? AlertTarget.organization] ??
        AlertTarget.organization;
  }

  /// Prefer [AlertDeliveryService.shouldUserReceiveAlert] for delivery checks.
  @Deprecated('Use AlertDeliveryService.shouldUserReceiveAlert')
  static bool shouldReceiveAlert(
    Map<String, dynamic> alert,
    String organizationId,
  ) {
    return alert['organization_id']?.toString() == organizationId.toString();
  }
}
