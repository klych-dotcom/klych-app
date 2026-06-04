/// Describes one row in [alert_targets] (+ optional [alert_target_users]).
class AlertTargetSpec {
  const AlertTargetSpec({
    required this.type,
    required this.displayLabel,
    this.departmentId,
    this.groupId,
    this.statusCode,
    this.userIds = const [],
  });

  final String type;
  final String displayLabel;
  final String? departmentId;
  final String? groupId;
  final String? statusCode;
  final List<String> userIds;

  static const organization = 'organization';
  static const department = 'department';
  static const group = 'group';
  static const status = 'status';
  static const users = 'users';

  factory AlertTargetSpec.orgWide() {
    return const AlertTargetSpec(
      type: organization,
      displayLabel: 'Вся організація',
    );
  }

  factory AlertTargetSpec.forDepartment({
    required String id,
    required String name,
  }) {
    return AlertTargetSpec(
      type: department,
      displayLabel: name,
      departmentId: id,
    );
  }

  factory AlertTargetSpec.forStatus({
    required String code,
    required String label,
  }) {
    return AlertTargetSpec(
      type: status,
      displayLabel: label,
      statusCode: code,
    );
  }

  factory AlertTargetSpec.forGroup({
    required String id,
    required String name,
  }) {
    return AlertTargetSpec(
      type: group,
      displayLabel: name,
      groupId: id,
    );
  }

  factory AlertTargetSpec.forUsers({
    required List<String> ids,
    required String displayLabel,
  }) {
    return AlertTargetSpec(
      type: users,
      displayLabel: displayLabel,
      userIds: ids,
    );
  }

  /// @deprecated Use [forUsers] for multi-user targets.
  factory AlertTargetSpec.forUser({
    required String id,
    required String callsign,
  }) {
    return AlertTargetSpec.forUsers(ids: [id], displayLabel: callsign);
  }

  Map<String, dynamic> toAlertTargetRow(String alertId) {
    return {
      'alert_id': alertId,
      'target_type': type,
      if (departmentId != null) 'department_id': departmentId,
      if (groupId != null) 'group_id': groupId,
      if (statusCode != null) 'status_code': statusCode,
    };
  }
}
