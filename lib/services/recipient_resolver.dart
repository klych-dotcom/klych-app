import '../models/alert_recipients_selection.dart';
import '../models/user_status.dart';

/// Single source of truth for who receives an alert.
class RecipientResolver {
  RecipientResolver({
    required this.selection,
    required this.users,
    required this.groups,
    this.excludeUserId,
  });

  final AlertRecipientsSelection selection;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> groups;
  final String? excludeUserId;

  late final List<Map<String, dynamic>> resolvedUsers = _computeUsers();
  late final List<String> resolvedUserIds =
      resolvedUsers.map((u) => u['id']?.toString()).whereType<String>().toList();

  int get count => resolvedUsers.length;
  bool get canSend => count > 0;

  List<Map<String, dynamic>> _computeUsers() {
    final ids = _computeIds();
    final byId = {
      for (final u in users)
        if (u['id'] != null) u['id'].toString(): u,
    };

    final result = ids
        .map((id) => byId[id])
        .whereType<Map<String, dynamic>>()
        .toList();

    result.sort(
      (a, b) => (a['callsign']?.toString() ?? '')
          .toLowerCase()
          .compareTo((b['callsign']?.toString() ?? '').toLowerCase()),
    );
    return result;
  }

  Set<String> _computeIds() {
    if (selection.orgWide) {
      return _activeUserIds();
    }

    final matched = <String>{};

    if (selection.hasFilterCriteria) {
      final groupMembers = _groupMemberIdsByUser();
      for (final user in users) {
        if (user['is_disabled'] == true) continue;
        final uid = user['id']?.toString();
        if (uid == null) continue;

        if (_matchesAnyCategory(user, uid, groupMembers)) {
          matched.add(uid);
        }
      }
    }

    for (final uid in selection.userIds) {
      final user = users.cast<Map<String, dynamic>?>().firstWhere(
            (u) => u?['id']?.toString() == uid,
            orElse: () => null,
          );
      if (user != null && user['is_disabled'] != true) {
        matched.add(uid);
      }
    }

    matched.removeWhere((id) => id == excludeUserId);
    return matched;
  }

  Set<String> _activeUserIds() {
    return users
        .where((u) => u['is_disabled'] != true)
        .map((u) => u['id']?.toString())
        .whereType<String>()
        .where((id) => id != excludeUserId)
        .toSet();
  }

  Map<String, Set<String>> _groupMemberIdsByUser() {
    final byGroup = <String, Set<String>>{};
    for (final group in groups) {
      final groupId = group['id']?.toString();
      if (groupId == null) continue;
      final members = group['group_members'] as List? ?? [];
      byGroup[groupId] = members
          .map((m) => (m as Map)['user_id']?.toString())
          .whereType<String>()
          .toSet();
    }
    return byGroup;
  }

  bool _matchesAnyCategory(
    Map<String, dynamic> user,
    String uid,
    Map<String, Set<String>> groupMembers,
  ) {
    if (selection.statusCodes.isNotEmpty) {
      final status = UserStatus.normalize(user['status']?.toString());
      if (selection.statusCodes.contains(status)) return true;
    }

    if (selection.departmentIds.isNotEmpty) {
      final deptId = user['department_id']?.toString();
      if (deptId != null && selection.departmentIds.contains(deptId)) {
        return true;
      }
    }

    if (selection.groupIds.isNotEmpty) {
      for (final groupId in selection.groupIds) {
        if (groupMembers[groupId]?.contains(uid) ?? false) return true;
      }
    }

    return false;
  }

  List<String> previewCallsigns({int limit = 8}) {
    return resolvedUsers
        .take(limit)
        .map((u) => u['callsign']?.toString() ?? '—')
        .toList();
  }
}

extension AlertRecipientsSelectionResolve on AlertRecipientsSelection {
  RecipientResolver resolveRecipients({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> groups,
    String? excludeUserId,
  }) {
    return RecipientResolver(
      selection: this,
      users: users,
      groups: groups,
      excludeUserId: excludeUserId,
    );
  }

  int estimateRecipientCount({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> groups,
    String? excludeUserId,
  }) {
    return resolveRecipients(
      users: users,
      groups: groups,
      excludeUserId: excludeUserId,
    ).count;
  }

  List<String> resolveDeliveryUserIds({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> groups,
    String? excludeUserId,
  }) {
    return resolveRecipients(
      users: users,
      groups: groups,
      excludeUserId: excludeUserId,
    ).resolvedUserIds;
  }

  List<Map<String, dynamic>> resolveDeliveryUsers({
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> groups,
    String? excludeUserId,
  }) {
    return resolveRecipients(
      users: users,
      groups: groups,
      excludeUserId: excludeUserId,
    ).resolvedUsers;
  }
}
