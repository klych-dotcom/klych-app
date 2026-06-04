import 'alert_target_spec.dart';
import 'user_status.dart';

/// Recipient specification: UNION across categories + explicit users + org-wide.
class AlertRecipientsSelection {
  AlertRecipientsSelection({
    Set<String>? statusCodes,
    Set<String>? departmentIds,
    Set<String>? groupIds,
    Set<String>? userIds,
    Map<String, String>? departmentNames,
    Map<String, String>? groupNames,
    Map<String, String>? userNames,
    this.orgWide = true,
  })  : statusCodes = statusCodes ?? {},
        departmentIds = departmentIds ?? {},
        groupIds = groupIds ?? {},
        userIds = userIds ?? {},
        departmentNames = departmentNames ?? {},
        groupNames = groupNames ?? {},
        userNames = userNames ?? {};

  final Set<String> statusCodes;
  final Set<String> departmentIds;
  final Set<String> groupIds;
  final Set<String> userIds;
  final Map<String, String> departmentNames;
  final Map<String, String> groupNames;
  final Map<String, String> userNames;
  final bool orgWide;

  bool get hasFilterCriteria =>
      statusCodes.isNotEmpty ||
      departmentIds.isNotEmpty ||
      groupIds.isNotEmpty;

  bool get hasManualUserSelection => userIds.isNotEmpty;

  bool get hasAnySelection =>
      orgWide || hasFilterCriteria || hasManualUserSelection;

  AlertRecipientsSelection copyWith({
    Set<String>? statusCodes,
    Set<String>? departmentIds,
    Set<String>? groupIds,
    Set<String>? userIds,
    Map<String, String>? departmentNames,
    Map<String, String>? groupNames,
    Map<String, String>? userNames,
    bool? orgWide,
  }) {
    return AlertRecipientsSelection(
      statusCodes: statusCodes ?? this.statusCodes,
      departmentIds: departmentIds ?? this.departmentIds,
      groupIds: groupIds ?? this.groupIds,
      userIds: userIds ?? this.userIds,
      departmentNames: departmentNames ?? this.departmentNames,
      groupNames: groupNames ?? this.groupNames,
      userNames: userNames ?? this.userNames,
      orgWide: orgWide ?? this.orgWide,
    );
  }

  AlertRecipientsSelection toggleOrgWide() {
    if (orgWide) {
      return copyWith(orgWide: false);
    }
    return AlertRecipientsSelection(orgWide: true);
  }

  AlertRecipientsSelection toggleStatus(String code) {
    final next = Set<String>.from(statusCodes);
    if (next.contains(code)) {
      next.remove(code);
    } else {
      next.add(code);
    }
    return copyWith(statusCodes: next, orgWide: false);
  }

  AlertRecipientsSelection toggleDepartment(String id, String name) {
    final nextIds = Set<String>.from(departmentIds);
    final nextNames = Map<String, String>.from(departmentNames);
    if (nextIds.contains(id)) {
      nextIds.remove(id);
      nextNames.remove(id);
    } else {
      nextIds.add(id);
      nextNames[id] = name;
    }
    return copyWith(
      departmentIds: nextIds,
      departmentNames: nextNames,
      orgWide: false,
    );
  }

  AlertRecipientsSelection toggleGroup(String id, String name) {
    final nextIds = Set<String>.from(groupIds);
    final nextNames = Map<String, String>.from(groupNames);
    if (nextIds.contains(id)) {
      nextIds.remove(id);
      nextNames.remove(id);
    } else {
      nextIds.add(id);
      nextNames[id] = name;
    }
    return copyWith(groupIds: nextIds, groupNames: nextNames, orgWide: false);
  }

  AlertRecipientsSelection toggleUser(String id, String callsign) {
    final nextIds = Set<String>.from(userIds);
    final nextNames = Map<String, String>.from(userNames);
    if (nextIds.contains(id)) {
      nextIds.remove(id);
      nextNames.remove(id);
    } else {
      nextIds.add(id);
      nextNames[id] = callsign;
    }
    return copyWith(userIds: nextIds, userNames: nextNames, orgWide: false);
  }

  AlertRecipientsSelection clear() => AlertRecipientsSelection(orgWide: true);

  List<AlertTargetSpec> toTargetSpecs({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> groups,
  }) {
    if (orgWide) return [AlertTargetSpec.orgWide()];

    final specs = <AlertTargetSpec>[];

    for (final code in statusCodes) {
      specs.add(AlertTargetSpec.forStatus(
        code: code,
        label: UserStatus.label(code),
      ));
    }

    for (final id in departmentIds) {
      specs.add(AlertTargetSpec.forDepartment(
        id: id,
        name: departmentNames[id] ?? id,
      ));
    }

    for (final id in groupIds) {
      specs.add(AlertTargetSpec.forGroup(
        id: id,
        name: groupNames[id] ?? id,
      ));
    }

    if (userIds.isNotEmpty) {
      specs.add(AlertTargetSpec.forUsers(
        ids: userIds.toList(),
        displayLabel: userIds.map((id) => userNames[id] ?? id).join(', '),
      ));
    }

    return specs;
  }

  String recipientsLabel({required int count}) => 'ОТРИМУВАЧІ ($count)';
}
