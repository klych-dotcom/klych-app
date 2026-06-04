import 'alert_constants.dart';

/// Server-side alert targeting configuration.
class AlertTargeting {
  static const bool serverSideEnabled = true;

  /// Future targeting dimensions (not active in this phase):
  /// - [AlertTarget.organization] — entire org
  /// - department_id — target a department
  /// - UserStatus.onDuty / deployed — target by operational status
  /// - operational_groups.id — target a saved group

  static bool isNonDefaultTarget(String target) {
    return target != AlertTarget.organization;
  }

  static const String disabledNotice =
      'Server-side targeting not yet enabled (coming soon)';

  static const String orgWideFallbackWarning =
      'Selected target is not active yet. Delivery is currently organization-wide.';
}
