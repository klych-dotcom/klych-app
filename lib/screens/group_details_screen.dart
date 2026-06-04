import 'package:flutter/material.dart';

import '../models/user_status.dart';
import '../services/group_service.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../utils/db_error_messages.dart';
import '../widgets/klych_components.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  bool loading = true;
  String? organizationId;
  String? currentUserId;
  Map<String, dynamic>? group;
  List<Map<String, dynamic>> orgUsers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    try {
      final profile = await UserOrgService.currentUserProfile();
      if (profile == null) return;

      organizationId = profile['organization_id']?.toString();
      currentUserId = profile['id']?.toString();

      group = await GroupService.fetchGroup(widget.groupId);

      if (organizationId != null) {
        orgUsers = await UserOrgService.fetchOrgUsers(organizationId!);
      }
    } catch (e) {
      debugPrint('GroupDetailsScreen._load: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  List<Map<String, dynamic>> get _members {
    final raw = group?['group_members'];
    if (raw is! List) return [];
    return raw
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
  }

  Set<String> get _memberUserIds => _members
      .map((m) => m['user_id']?.toString())
      .whereType<String>()
      .toSet();

  String _memberCallsign(Map<String, dynamic> member) {
    final users = member['users'];
    if (users is Map) return users['callsign']?.toString() ?? '—';
    final uid = member['user_id']?.toString();
    if (uid == null) return '—';
    final user = orgUsers.cast<Map<String, dynamic>?>().firstWhere(
          (u) => u?['id']?.toString() == uid,
          orElse: () => null,
        );
    return user?['callsign']?.toString() ?? uid.substring(0, 8);
  }

  String _memberStatus(Map<String, dynamic> member) {
    final users = member['users'];
    if (users is Map) {
      return UserStatus.label(users['status']?.toString());
    }
    return '—';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _renameGroup() async {
    if (group == null) return;

    final controller = TextEditingController(text: group!['name']?.toString());
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Перейменувати', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('СКАСУВАТИ')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ЗБЕРЕГТИ'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      await GroupService.renameGroup(groupId: widget.groupId, name: name);
      await _load();
      if (mounted) _showSuccess('Групу перейменовано');
    } catch (e) {
      _showError(DbErrorMessages.from(e));
    }
  }

  Future<void> _deleteGroup() async {
    final name = group?['name']?.toString() ?? '—';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Видалити групу?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Група «$name» та всі її учасники будуть видалені з групи.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ВИДАЛИТИ', style: TextStyle(color: KlychTheme.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await GroupService.deleteGroup(widget.groupId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(DbErrorMessages.from(e));
    }
  }

  Future<void> _addMembers() async {
    if (currentUserId == null) return;

    final candidates = orgUsers.where((u) {
      if (u['is_disabled'] == true) return false;
      final id = u['id']?.toString();
      return id != null && !_memberUserIds.contains(id);
    }).toList();

    if (candidates.isEmpty) {
      _showError('Немає користувачів для додавання');
      return;
    }

    final selected = <String>{};
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Додати учасників', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              height: 320,
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (_, i) {
                  final user = candidates[i];
                  final userId = user['id']!.toString();
                  return CheckboxListTile(
                    value: selected.contains(userId),
                    activeColor: Colors.orange,
                    onChanged: (checked) {
                      setDialogState(() {
                        if (checked == true) {
                          selected.add(userId);
                        } else {
                          selected.remove(userId);
                        }
                      });
                    },
                    title: Text(
                      user['callsign']?.toString() ?? '—',
                      style: const TextStyle(color: Colors.white),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ')),
              TextButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                child: const Text('ДОДАТИ'),
              ),
            ],
          );
        },
      ),
    );

    if (added != true || selected.isEmpty) return;

    try {
      await GroupService.addMembers(
        groupId: widget.groupId,
        userIds: selected.toList(),
        addedByUserId: currentUserId,
      );
      await _load();
      if (mounted) _showSuccess('Додано ${selected.length} учасників');
    } catch (e) {
      _showError(DbErrorMessages.from(e));
    }
  }

  Future<void> _removeMember(String userId, String callsign) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Видалити з групи?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Прибрати $callsign з цієї групи?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ВИДАЛИТИ', style: TextStyle(color: KlychTheme.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await GroupService.removeMember(groupId: widget.groupId, userId: userId);
      await _load();
      if (mounted) _showSuccess('Учасника видалено');
    } catch (e) {
      _showError(DbErrorMessages.from(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupName = group?['name']?.toString() ?? '—';
    final members = _members;

    return Scaffold(
      backgroundColor: KlychTheme.background,
      appBar: AppBar(
        title: Text(groupName),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Перейменувати',
            onPressed: group == null ? null : _renameGroup,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: KlychTheme.alertRed),
            tooltip: 'Видалити групу',
            onPressed: group == null ? null : _deleteGroup,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : group == null
              ? const KlychEmptyState(message: 'Групу не знайдено')
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$groupName (${members.length})',
                              style: KlychTheme.titleLarge,
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _addMembers,
                            icon: const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text('ДОДАТИ'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: members.isEmpty
                          ? const KlychEmptyState(message: 'Немає учасників')
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: KlychTheme.spaceXl,
                              ),
                              itemCount: members.length,
                              itemBuilder: (_, i) {
                                final member = Map<String, dynamic>.from(members[i] as Map);
                                final userId = member['user_id']?.toString();
                                final callsign = _memberCallsign(member);

                                return KlychCard(
                                  margin: const EdgeInsets.only(bottom: KlychTheme.spaceSm),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: KlychTheme.spaceMd,
                                    vertical: KlychTheme.spaceXs,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              callsign.toUpperCase(),
                                              style: KlychTheme.titleMedium.copyWith(fontSize: 14),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              _memberStatus(member),
                                              style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline,
                                            color: KlychTheme.alertRed),
                                        onPressed: userId == null
                                            ? null
                                            : () => _removeMember(userId, callsign),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}
