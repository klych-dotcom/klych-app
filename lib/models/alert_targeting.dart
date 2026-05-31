import 'alert_constants.dart';

/// Server-side alert targeting configuration.
///
/// When [serverSideEnabled] is false, all alerts are delivered organization-wide
/// regardless of UI target selection. Enable after DB + delivery pipeline migration.
class AlertTargeting {
  static const bool serverSideEnabled = false;

  static bool isNonDefaultTarget(String target) {
    return target != AlertTarget.organization;
  }

  static const String disabledNotice =
      'Server-side targeting not yet enabled (coming soon)';

  static const String orgWideFallbackWarning =
      'Selected target is not active yet. Delivery is currently organization-wide.';
}
