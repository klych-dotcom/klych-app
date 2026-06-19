import 'package:flutter/material.dart';

import '../models/alert_recipients_selection.dart';
import '../models/user_role.dart';
import '../services/group_service.dart';
import '../services/user_org_service.dart';
import '../utils/db_error_messages.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import '../widgets/org_user_widgets.dart';
import 'admin_user_detail_screen.dart';
import 'group_details_screen.dart';
import 'groups_screen.dart';
import 'leader_home_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.adminMode = false});

  final bool adminMode;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool loading = true;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> groups = [];
  bool isLeader = false;
  String? organizationId;
  String? currentUserId;

  final Set<String> _selectedUserIds = {};
  final Map<String, String> _selectedUserNames = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool get _selectionMode => !widget.adminMode && isLeader;
  bool get _hasSelection => _selectedUserIds.isNotEmpty;

  List<Map<String, dynamic>> get _visibleUsers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return users;
    return users.where((u) {
      final callsign = u['callsign']?.toString().toLowerCase() ?? '';
      return callsign.contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final profile = await UserOrgService.currentUserProfile();
      if (profile == null) return;

      organizationId = profile['organization_id']?.toString();
      currentUserId = profile['id']?.toString();
      isLeader = UserRole.isLeader(UserRole.authorizationRole(profile));

      users = await UserOrgService.fetchOrgUsers(
        profile['organization_id'].toString(),
      );

      if (organizationId != null && isLeader) {
        groups = await GroupService.fetchGroups(organizationId!);
      }
    } catch (e) {
      debugPrint('$e');
    }

    if (mounted) setState(() => loading = false);
  }

  void _toggleUserSelection(Map<String, dynamic> user) {
    final userId = user['id']?.toString();
    if (userId == null) return;

    setState(() {
      if (_selectedUserIds.contains(userId)) {
        _selectedUserIds.remove(userId);
        _selectedUserNames.remove(userId);
      } else {
        _selectedUserIds.add(userId);
        _selectedUserNames[userId] = user['callsign']?.toString() ?? '—';
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUserIds.clear();
      _selectedUserNames.clear();
    });
  }

  Future<void> _createGroupFromSelection() async {
    if (_selectedUserIds.isEmpty ||
        organizationId == null ||
        currentUserId == null) {
      return;
    }

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Нова група', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Назва групи'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('СКАСУВАТИ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('СТВОРИТИ'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final memberCount = _selectedUserIds.length;

    try {
      final group = await GroupService.createGroupWithMembers(
        organizationId: organizationId!,
        name: name,
        createdByUserId: currentUserId!,
        memberUserIds: _selectedUserIds.toList(),
      );

      if (!mounted) return;

      final refreshed = await GroupService.fetchGroups(organizationId!);
      final groupId = group['id']?.toString();

      if (!refreshed.any((g) => g['id']?.toString() == groupId)) {
        throw Exception('Групу збережено, але не вдалося завантажити список');
      }

      groups = refreshed;

      if (!mounted) return;

      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Групу «$name» створено ($memberCount учасників)'),
          action: SnackBarAction(
            label: 'ВІДКРИТИ',
            onPressed: () {
              if (groupId == null) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupDetailsScreen(groupId: groupId),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DbErrorMessages.from(e, fallback: 'Помилка: $e')),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _addToExistingGroup() async {
    if (_selectedUserIds.isEmpty || currentUserId == null) return;

    if (groups.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Спочатку створіть групу')),
      );
      return;
    }

    String? selectedGroupId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text('Додати до групи', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              height: 280,
              child: ListView.builder(
                itemCount: groups.length,
                itemBuilder: (_, i) {
                  final g = groups[i];
                  final id = g['id']?.toString();
                  if (id == null) return const SizedBox.shrink();
                  final selected = selectedGroupId == id;
                  return ListTile(
                    selected: selected,
                    selectedColor: Colors.orange,
                    title: Text(
                      g['name']?.toString() ?? '—',
                      style: TextStyle(
                        color: selected ? Colors.orange : Colors.white,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(Icons.check_circle, color: Colors.orange)
                        : null,
                    onTap: () => setDialogState(() => selectedGroupId = id),
                  );
                },
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ')),
              TextButton(
                onPressed: selectedGroupId == null ? null : () => Navigator.pop(context, true),
                child: const Text('ДОДАТИ'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedGroupId == null) return;

    try {
      await GroupService.addMembers(
        groupId: selectedGroupId!,
        userIds: _selectedUserIds.toList(),
        addedByUserId: currentUserId,
      );

      if (organizationId != null) {
        groups = await GroupService.fetchGroups(organizationId!);
      }

      if (!mounted) return;

      final count = _selectedUserIds.length;
      _clearSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Додано $count учасників до групи')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(DbErrorMessages.from(e, fallback: 'Помилка: $e')),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  void _alertSelectedUsers() {
    if (_selectedUserIds.isEmpty) return;

    // Manual selection must target ONLY the chosen users — never fall back to
    // org-wide (the constructor defaults orgWide to true).
    final recipients = AlertRecipientsSelection(
      userIds: Set<String>.from(_selectedUserIds),
      userNames: Map<String, String>.from(_selectedUserNames),
      orgWide: false,
    );

    // Replace the stack so we land on a single LeaderHomeScreen instance
    // (no duplicate alert subscriptions / audio players).
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderHomeScreen(initialRecipients: recipients),
      ),
      (route) => false,
    );
  }

  Future<void> _openUser(Map<String, dynamic> user) async {
    if (!widget.adminMode) return;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUserDetailScreen(user: user),
      ),
    );

    if (changed == true) await loadUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KlychTheme.background,
      appBar: AppBar(
        title: Text(widget.adminMode ? 'КОРИСТУВАЧІ' : 'КОРИСТУВАЧІ'),
        actions: [
          if (_selectionMode && _hasSelection)
            TextButton(
              onPressed: _clearSelection,
              child: const Text('СКИНУТИ', style: TextStyle(color: Colors.white54)),
            ),
          if (!widget.adminMode && isLeader)
            IconButton(
              icon: const Icon(Icons.groups_outlined, color: Colors.white),
              tooltip: 'Групи',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupsScreen()),
              ),
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KlychTheme.spaceLg,
                    KlychTheme.spaceSm,
                    KlychTheme.spaceLg,
                    0,
                  ),
                  child: KlychSearchField(
                    controller: _searchController,
                    onChanged: (q) => setState(() => _searchQuery = q),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: loadUsers,
                    color: KlychTheme.accent,
                    child: _visibleUsers.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              KlychEmptyState(message: 'Немає користувачів'),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(KlychTheme.spaceLg),
                            itemCount: _visibleUsers.length,
                            itemBuilder: (_, index) {
                              final user = _visibleUsers[index];
                            final userId = user['id']?.toString();
                            final selected = userId != null &&
                                _selectedUserIds.contains(userId);

                            return UserOrgListTile(
                              user: user,
                              compact: true,
                              selected: selected,
                              onTap: widget.adminMode
                                  ? () => _openUser(user)
                                  : _selectionMode
                                      ? () => _toggleUserSelection(user)
                                      : null,
                              leading: _selectionMode
                                  ? Checkbox(
                                      value: selected,
                                      activeColor: Colors.orange,
                                      onChanged: userId == null
                                          ? null
                                          : (_) => _toggleUserSelection(user),
                                    )
                                  : null,
                              trailing: widget.adminMode
                                  ? const Icon(
                                      Icons.chevron_right,
                                      color: Colors.white38,
                                    )
                                  : selected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.orange,
                                        )
                                      : null,
                            );
                          },
                        ),
                  ),
                ),
                if (_selectionMode && _hasSelection)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1A1A1C),
                      border: Border(top: BorderSide(color: Colors.white12)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'ОТРИМУВАЧІ (${_selectedUserIds.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: _createGroupFromSelection,
                            icon: const Icon(Icons.group_add_outlined),
                            label: const Text('СТВОРИТИ ГРУПУ'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _addToExistingGroup,
                            icon: const Icon(Icons.group_outlined),
                            label: const Text('ДОДАТИ ДО ГРУПИ'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                          const SizedBox(height: 8),
                          KlychPrimaryButton(
                            label: 'ОПОВІСТИТИ',
                            icon: Icons.notifications_active_outlined,
                            onPressed: _alertSelectedUsers,
                            color: KlychTheme.alertRed,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
