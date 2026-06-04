import 'package:alert_app/models/alert_recipients_selection.dart';
import 'package:alert_app/models/alert_target_spec.dart';
import 'package:alert_app/models/user_status.dart';
import 'package:alert_app/services/alert_delivery_service.dart';
import 'package:alert_app/services/recipient_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertDeliveryService.resolveFromTargetRows', () {
    final orgUsers = [
      {
        'id': 'u1',
        'department_id': 'd1',
        'status': UserStatus.available,
        'is_disabled': false,
      },
      {
        'id': 'u2',
        'department_id': 'd2',
        'status': UserStatus.onDuty,
        'is_disabled': false,
      },
      {
        'id': 'u3',
        'department_id': 'd1',
        'status': UserStatus.unavailable,
        'is_disabled': true,
      },
    ];

    test('organization target reaches all active users', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.organization},
        ],
        explicitUserIds: {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {},
      );

      expect(recipients, {'u1', 'u2'});
    });

    test('department target reaches only matching department', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.department, 'department_id': 'd1'},
        ],
        explicitUserIds: {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {},
      );

      expect(recipients, {'u1'});
    });

    test('status target reaches only matching status', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.status, 'status_code': UserStatus.onDuty},
        ],
        explicitUserIds: {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {},
      );

      expect(recipients, {'u2'});
    });

    test('group target reaches only group members', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.group, 'group_id': 'g1'},
        ],
        explicitUserIds: {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {'g1': {'u2'}},
      );

      expect(recipients, {'u2'});
    });

    test('explicit users target reaches only listed users', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.users},
        ],
        explicitUserIds: {'u1'},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {},
      );

      expect(recipients, {'u1'});
    });

    test('union across multiple target rows', () {
      final recipients = AlertDeliveryService.resolveFromTargetRows(
        targets: [
          {'target_type': AlertTargetSpec.department, 'department_id': 'd1'},
          {'target_type': AlertTargetSpec.status, 'status_code': UserStatus.onDuty},
        ],
        explicitUserIds: {},
        orgUsers: orgUsers,
        groupMemberIdsByGroup: {},
      );

      expect(recipients, {'u1', 'u2'});
    });
  });

  group('RecipientResolver UNION logic', () {
    final users = [
      {
        'id': 'u1',
        'department_id': 'hq',
        'status': UserStatus.available,
        'is_disabled': false,
        'callsign': 'BOSS',
      },
      {
        'id': 'u2',
        'department_id': 'hq',
        'status': UserStatus.deployed,
        'is_disabled': false,
        'callsign': 'CRUZO',
      },
      {
        'id': 'u3',
        'department_id': 'field',
        'status': UserStatus.deployed,
        'is_disabled': false,
        'callsign': 'FOLK',
      },
    ];

    final groups = [
      {
        'id': 'g1',
        'name': 'Leaders',
        'group_members': [
          {'user_id': 'u1'},
          {'user_id': 'u2'},
        ],
      },
    ];

    test('status + department + group unions all unique users', () {
      final selection = AlertRecipientsSelection(
        orgWide: false,
        statusCodes: {UserStatus.available},
        departmentIds: {'hq'},
        groupIds: {'g1'},
      );

      final resolved = selection.resolveRecipients(users: users, groups: groups);
      expect(resolved.count, 2);
      expect(resolved.resolvedUserIds.toSet(), {'u1', 'u2'});
    });

    test('orgWide selects all active users', () {
      final selection = AlertRecipientsSelection(orgWide: true);
      final resolved = selection.resolveRecipients(users: users, groups: groups);
      expect(resolved.count, 3);
    });

    test('explicit users are added to union', () {
      final selection = AlertRecipientsSelection(
        orgWide: false,
        statusCodes: {UserStatus.available},
        userIds: {'u3'},
        userNames: {'u3': 'FOLK'},
      );

      final resolved = selection.resolveRecipients(users: users, groups: groups);
      expect(resolved.resolvedUserIds.toSet(), {'u1', 'u3'});
    });

    test('toTargetSpecs emits separate rows per category', () {
      final selection = AlertRecipientsSelection(
        orgWide: false,
        statusCodes: {UserStatus.available},
        departmentIds: {'hq'},
        groupIds: {'g1'},
      );

      final specs = selection.toTargetSpecs(users: users, groups: groups);
      expect(specs.length, 3);
      expect(specs.where((s) => s.type == AlertTargetSpec.status).length, 1);
      expect(specs.where((s) => s.type == AlertTargetSpec.department).length, 1);
      expect(specs.where((s) => s.type == AlertTargetSpec.group).length, 1);
    });

    test('UI count matches delivery ids', () {
      final selection = AlertRecipientsSelection(
        orgWide: false,
        departmentIds: {'hq'},
        statusCodes: {UserStatus.deployed},
      );

      final resolved = selection.resolveRecipients(users: users, groups: groups);
      expect(
        selection.estimateRecipientCount(users: users, groups: groups),
        resolved.count,
      );
      expect(resolved.resolvedUserIds.toSet(), {'u1', 'u2', 'u3'});
      expect(resolved.count, 3);
    });
  });
}
