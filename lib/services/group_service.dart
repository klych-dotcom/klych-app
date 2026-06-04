import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../utils/db_error_messages.dart';

/// Operational groups — alert targeting via [groupId].
class GroupService {
  /// Disambiguates two FKs from group_members → users (user_id, added_by).
  static const _memberSelect =
      'group_id, user_id, users!group_members_user_id_fkey(id, callsign, status)';

  static Future<Map<String, dynamic>?> fetchGroup(String groupId) async {
    final group = await supabase
        .from('operational_groups')
        .select()
        .eq('id', groupId)
        .maybeSingle();

    if (group == null) return null;

    final members = await _fetchMembers(groupId);
    return {
      ...Map<String, dynamic>.from(group),
      'group_members': members,
    };
  }

  static Future<List<Map<String, dynamic>>> _fetchMembers(String groupId) async {
    try {
      final rows = await supabase
          .from('group_members')
          .select(_memberSelect)
          .eq('group_id', groupId);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('GroupService._fetchMembers embed failed: $e');
      final rows = await supabase
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId);
      return List<Map<String, dynamic>>.from(rows);
    }
  }

  /// Batch member lookup — one query for all groups in the org.
  static Future<Map<String, Set<String>>> fetchGroupMemberIdsByGroup(
    String organizationId,
  ) async {
    final groups = await supabase
        .from('operational_groups')
        .select('id')
        .eq('organization_id', organizationId);

    final groupIds = List<Map<String, dynamic>>.from(groups)
        .map((g) => g['id']?.toString())
        .whereType<String>()
        .toList();

    if (groupIds.isEmpty) return {};

    final rows = await supabase
        .from('group_members')
        .select('group_id, user_id')
        .inFilter('group_id', groupIds);

    final result = {for (final id in groupIds) id: <String>{}};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final groupId = row['group_id']?.toString();
      final userId = row['user_id']?.toString();
      if (groupId != null && userId != null) {
        result.putIfAbsent(groupId, () => {}).add(userId);
      }
    }
    return result;
  }

  static Future<List<Map<String, dynamic>>> fetchGroups(
    String organizationId,
  ) async {
    debugPrint('GroupService.fetchGroups org=$organizationId');

    final groups = await supabase
        .from('operational_groups')
        .select()
        .eq('organization_id', organizationId)
        .order('name');

    final groupList = List<Map<String, dynamic>>.from(groups);
    final groupIds = groupList
        .map((g) => g['id']?.toString())
        .whereType<String>()
        .toList();

    final membersByGroup = <String, List<Map<String, dynamic>>>{};
    if (groupIds.isNotEmpty) {
      try {
        final rows = await supabase
            .from('group_members')
            .select(_memberSelect)
            .inFilter('group_id', groupIds);

        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final groupId = row['group_id']?.toString();
          if (groupId == null) continue;
          membersByGroup.putIfAbsent(groupId, () => []).add(row);
        }
      } catch (e) {
        debugPrint('GroupService.fetchGroups batch embed failed: $e');
        final memberIdsByGroup =
            await fetchGroupMemberIdsByGroup(organizationId);
        for (final entry in memberIdsByGroup.entries) {
          membersByGroup[entry.key] = entry.value
              .map((userId) => {'user_id': userId})
              .toList();
        }
      }
    }

    final result = groupList
        .map(
          (group) => {
            ...group,
            'group_members': membersByGroup[group['id']?.toString()] ?? [],
          },
        )
        .toList();

    debugPrint('GroupService.fetchGroups returned ${result.length} groups');
    return result;
  }

  static Future<Map<String, dynamic>> createGroupWithMembers({
    required String organizationId,
    required String name,
    required String createdByUserId,
    required List<String> memberUserIds,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw Exception('Введіть назву групи');
    }

    debugPrint(
      'GroupService.createGroupWithMembers org=$organizationId '
      'name=$trimmed members=${memberUserIds.length}',
    );

    final group = await createGroup(
      organizationId: organizationId,
      name: trimmed,
      createdByUserId: createdByUserId,
    );

    final groupId = group['id'].toString();
    debugPrint('GroupService.createGroupWithMembers created id=$groupId');

    if (memberUserIds.isNotEmpty) {
      try {
        await supabase.from('group_members').insert(
          memberUserIds
              .map(
                (userId) => {
                  'group_id': groupId,
                  'user_id': userId,
                  'added_by': createdByUserId,
                },
              )
              .toList(),
        );
        debugPrint(
          'GroupService.createGroupWithMembers inserted '
          '${memberUserIds.length} members',
        );
      } on PostgrestException catch (e) {
        debugPrint('GroupService.createGroupWithMembers member error: $e');
        throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося додати учасників'));
      }
    }

    final verify = await supabase
        .from('operational_groups')
        .select('id, name, organization_id')
        .eq('id', groupId)
        .maybeSingle();

    debugPrint('GroupService.createGroupWithMembers verify=$verify');

    if (verify == null) {
      throw Exception('Групу створено, але не вдалося підтвердити збереження');
    }

    return group;
  }

  static Future<Map<String, dynamic>> createGroup({
    required String organizationId,
    required String name,
    required String createdByUserId,
  }) async {
    try {
      final row = await supabase
          .from('operational_groups')
          .insert({
            'organization_id': organizationId,
            'name': name.trim(),
            'created_by': createdByUserId,
          })
          .select()
          .single();

      return Map<String, dynamic>.from(row);
    } on PostgrestException catch (e) {
      debugPrint('GroupService.createGroup error: $e');
      throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося створити групу'));
    }
  }

  static Future<void> renameGroup({
    required String groupId,
    required String name,
  }) async {
    try {
      await supabase
          .from('operational_groups')
          .update({'name': name.trim()})
          .eq('id', groupId);
    } on PostgrestException catch (e) {
      throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося перейменувати групу'));
    }
  }

  static Future<void> deleteGroup(String groupId) async {
    try {
      await supabase.from('group_members').delete().eq('group_id', groupId);
      await supabase.from('operational_groups').delete().eq('id', groupId);
    } on PostgrestException catch (e) {
      throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося видалити групу'));
    }
  }

  static Future<void> addMembers({
    required String groupId,
    required List<String> userIds,
    String? addedByUserId,
  }) async {
    if (userIds.isEmpty) return;

    final rows = userIds
        .map(
          (userId) => {
            'group_id': groupId,
            'user_id': userId,
            if (addedByUserId != null) 'added_by': addedByUserId,
          },
        )
        .toList();

    try {
      await supabase.from('group_members').insert(rows);
    } on PostgrestException catch (e) {
      throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося додати учасників'));
    }
  }

  static Future<void> addMember({
    required String groupId,
    required String userId,
    String? addedByUserId,
  }) async {
    await supabase.from('group_members').insert({
      'group_id': groupId,
      'user_id': userId,
      if (addedByUserId != null) 'added_by': addedByUserId,
    });
  }

  static Future<void> removeMember({
    required String groupId,
    required String userId,
  }) async {
    try {
      await supabase
          .from('group_members')
          .delete()
          .eq('group_id', groupId)
          .eq('user_id', userId);
    } on PostgrestException catch (e) {
      throw Exception(DbErrorMessages.from(e, fallback: 'Не вдалося видалити учасника'));
    }
  }
}
