import '../models/alert_constants.dart';
import '../models/alert_targeting.dart';

class AlertUtils {
  static bool isRedAlert(String? type) {
    final normalized = type?.trim().toUpperCase();
    return normalized == AlertLevel.red ||
        normalized == 'GENERAL' ||
        normalized == 'TEST';
  }

  static bool isGreenAlert(String? type) {
    return type?.trim().toUpperCase() == AlertLevel.green;
  }

  static String levelLabel(String? type) {
    if (isGreenAlert(type)) return AlertLevel.green;
    if (isRedAlert(type)) return AlertLevel.red;
    return type?.toUpperCase() ?? AlertLevel.red;
  }

  /// Label for display — reflects persisted target only when server targeting is on.
  static String targetLabel(String? storedTarget) {
    if (!AlertTargeting.serverSideEnabled) {
      return AlertTarget.labels[AlertTarget.organization]!;
    }

    return AlertTarget.labels[storedTarget ?? AlertTarget.organization] ??
        AlertTarget.organization;
  }

  /// Org-scoped delivery check. Role/target filtering is server-side only.
  ///
  /// TODO: When [AlertTargeting.serverSideEnabled], rely on server recipient
  /// lists or persisted [alert['target']] — do not filter by role here.
  static bool shouldReceiveAlert(
    Map<String, dynamic> alert,
    String organizationId,
  ) {
    return alert['organization_id']?.toString() == organizationId.toString();
  }
}
