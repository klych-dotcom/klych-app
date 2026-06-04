import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/alert_exceptions.dart';
import '../models/alert_recipients_selection.dart';
import '../services/department_service.dart';
import '../services/group_service.dart';
import '../services/recipient_resolver.dart';
import '../services/user_org_service.dart';
import '../utils/department_labels.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import '../widgets/org_user_widgets.dart';
import 'groups_screen.dart';
import 'leader_home_screen.dart';
import 'users_screen.dart';

/// Leader organization — filter recipients and compose alerts.
class LeaderOrgScreen extends StatefulWidget {
  const LeaderOrgScreen({super.key, this.selectRecipientsMode = false});

  final bool selectRecipientsMode;

  @override
  State<LeaderOrgScreen> createState() => _LeaderOrgScreenState();
}

class _LeaderOrgScreenState extends State<LeaderOrgScreen> {
  bool loading = true;
  String? organizationId;
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> departments = [];
  List<Map<String, dynamic>> groups = [];
  RealtimeChannel? _usersChannel;

  AlertRecipientsSelection _recipients = AlertRecipientsSelection();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _usersChannel?.unsubscribe();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _load();
    _subscribe();
  }

  Future<void> _load() async {
    try {
      final profile = await UserOrgService.currentUserProfile();
      if (profile == null) return;

      organizationId = profile['organization_id']?.toString();
      if (organizationId == null) return;

      users = await UserOrgService.fetchOrgUsers(organizationId!);
      departments = await DepartmentService.fetchActive(organizationId!);
      groups = await GroupService.fetchGroups(organizationId!);
      _invalidateResolver();
    } catch (e) {
      debugPrint('LeaderOrgScreen._load: $e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _subscribe() {
    if (organizationId == null) return;

    _usersChannel?.unsubscribe();
    _usersChannel = UserOrgService.subscribeUserChanges(
      organizationId: organizationId!,
      onChange: (payload) async {
        await _applyUserChange(payload);
      },
    );
  }

  Future<void> _applyUserChange(PostgresChangePayload payload) async {
    final userId = payload.newRecord['id']?.toString();
    if (userId == null || !mounted) return;

    try {
      final updated = await supabase
          .from('users')
          .select(UserOrgService.userSelect)
          .eq('id', userId)
          .maybeSingle();

      if (!mounted || updated == null) return;

      setState(() {
        final index = users.indexWhere((u) => u['id']?.toString() == userId);
        if (index >= 0) {
          users[index] = Map<String, dynamic>.from(updated);
        }
        _invalidateResolver();
      });
    } catch (e) {
      debugPrint('LeaderOrgScreen._applyUserChange: $e');
    }
  }

  // Cached so recipient resolution runs once per selection/data change instead
  // of on every rebuild (e.g. while typing in the search field).
  RecipientResolver? _resolverCache;

  RecipientResolver get _resolver => _resolverCache ??=
      _recipients.resolveRecipients(users: users, groups: groups);

  void _invalidateResolver() => _resolverCache = null;

  /// The list below the filters is a live preview of the exact UNION recipient
  /// set (status ∪ department ∪ group ∪ explicit users). When a search query is
  /// present we expose the full directory so any user can still be added.
  List<Map<String, dynamic>> _visibleUsers(RecipientResolver resolved) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return resolved.resolvedUsers;

    return users.where((u) {
      if (u['is_disabled'] == true) return false;
      final callsign = u['callsign']?.toString().toLowerCase() ?? '';
      return callsign.contains(query);
    }).toList();
  }

  void _setRecipients(AlertRecipientsSelection next) {
    _invalidateResolver();
    setState(() => _recipients = next);
  }

  void _createAlert() {
    if (!_resolver.canSend) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(NoRecipientsException().message)),
      );
      return;
    }

    if (widget.selectRecipientsMode) {
      Navigator.pop(context, _recipients);
      return;
    }

    // Replace the whole stack so we never accumulate multiple live
    // LeaderHomeScreen instances (duplicate alert subscriptions / players).
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => LeaderHomeScreen(initialRecipients: _recipients),
      ),
      (route) => false,
    );
  }

  int _groupMemberCount(Map<String, dynamic> group) {
    return (group['group_members'] as List? ?? []).length;
  }

  @override
  Widget build(BuildContext context) {
    final counts = UserOrgService.countByStatus(users);
    final resolved = _resolver;
    final searchableUsers = _visibleUsers(resolved);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectRecipientsMode ? 'ОТРИМУВАЧІ' : 'ОРГАНІЗАЦІЯ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.groups_outlined),
            tooltip: 'Групи',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const GroupsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'Користувачі',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UsersScreen(adminMode: false)),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: KlychTheme.accent,
                    child: ListView(
                      padding: const EdgeInsets.all(KlychTheme.spaceLg),
                      children: [
                        KlychFilterChip(
                          label: 'Вся організація',
                          selected: _recipients.orgWide,
                          onSelected: (_) => _setRecipients(_recipients.toggleOrgWide()),
                          selectedColor: KlychTheme.alertRed,
                        ),
                        const SizedBox(height: KlychTheme.spaceLg),
                        const KlychSectionHeader(title: 'СТАТУСИ'),
                        OrgStatusSummary(
                          counts: counts,
                          selectedStatuses: _recipients.statusCodes,
                          onStatusToggle: (status) {
                            _setRecipients(_recipients.toggleStatus(status));
                          },
                        ),
                        const SizedBox(height: KlychTheme.spaceLg),
                        const KlychSectionHeader(title: 'ПІДРОЗДІЛИ'),
                        DepartmentFilterChips(
                          departments: departments,
                          selectedDepartmentIds: _recipients.departmentIds,
                          onDepartmentToggle: (id, name) {
                            _setRecipients(
                              _recipients.toggleDepartment(
                                id,
                                DepartmentLabels.localize(name),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: KlychTheme.spaceLg),
                        const KlychSectionHeader(title: 'ГРУПИ'),
                        if (groups.isEmpty)
                          Text('—', style: KlychTheme.bodyMedium)
                        else
                          Wrap(
                            spacing: KlychTheme.spaceSm,
                            runSpacing: KlychTheme.spaceSm,
                            children: groups.map((group) {
                              final id = group['id']?.toString();
                              if (id == null) return const SizedBox.shrink();
                              final name = group['name']?.toString() ?? '—';
                              final memberCount = _groupMemberCount(group);
                              final selected = _recipients.groupIds.contains(id);
                              return KlychFilterChip(
                                label: '$name ($memberCount)',
                                selected: selected,
                                onSelected: (_) {
                                  _setRecipients(_recipients.toggleGroup(id, name));
                                },
                                selectedColor: KlychTheme.statusOnDuty,
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: KlychTheme.spaceLg),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'КОРИСТУВАЧІ',
                                style: KlychTheme.labelCaps,
                              ),
                            ),
                            if (_recipients.hasAnySelection && !_recipients.orgWide)
                              TextButton(
                                onPressed: () => _setRecipients(_recipients.clear()),
                                child: const Text('СКИНУТИ'),
                              ),
                          ],
                        ),
                        const SizedBox(height: KlychTheme.spaceSm),
                        KlychSearchField(
                          controller: _searchController,
                          onChanged: (q) => setState(() => _searchQuery = q),
                        ),
                        const SizedBox(height: KlychTheme.spaceSm),
                        ...searchableUsers.map((user) {
                          final userId = user['id']?.toString();
                          final selected =
                              userId != null && _recipients.userIds.contains(userId);
                          return UserOrgListTile(
                            user: user,
                            compact: true,
                            selected: selected,
                            onTap: userId == null
                                ? null
                                : () {
                                    _setRecipients(
                                      _recipients.toggleUser(
                                        userId,
                                        user['callsign']?.toString() ?? '—',
                                      ),
                                    );
                                  },
                            trailing: selected
                                ? Icon(Icons.check_circle,
                                    color: KlychTheme.accent, size: 18)
                                : null,
                          );
                        }),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(KlychTheme.spaceLg),
                  decoration: BoxDecoration(
                    color: KlychTheme.surface,
                    border: Border(top: BorderSide(color: KlychTheme.borderSubtle)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RecipientPreviewPanel(count: resolved.count),
                        const SizedBox(height: KlychTheme.spaceMd),
                        KlychPrimaryButton(
                          label: widget.selectRecipientsMode
                              ? 'ПІДТВЕРДИТИ'
                              : 'СТВОРИТИ ОПОВІЩЕННЯ',
                          icon: Icons.notifications_active_outlined,
                          onPressed: resolved.canSend ? _createAlert : null,
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
