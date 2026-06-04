import 'package:flutter/material.dart';

import '../services/group_service.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'group_details_screen.dart';

/// Group list — tap opens [GroupDetailsScreen].
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  bool loading = true;
  String? organizationId;
  String? currentUserId;
  List<Map<String, dynamic>> groups = [];

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

      if (organizationId != null) {
        groups = await GroupService.fetchGroups(organizationId!);
      }
    } catch (e) {
      debugPrint('GroupsScreen._load: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _createGroup() async {
    if (organizationId == null || currentUserId == null) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Нова група'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Назва групи'),
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

    try {
      final group = await GroupService.createGroup(
        organizationId: organizationId!,
        name: name,
        createdByUserId: currentUserId!,
      );

      if (!mounted) return;

      final groupId = group['id']?.toString();
      if (groupId != null) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => GroupDetailsScreen(groupId: groupId)),
        );
      }

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Помилка: $e'), backgroundColor: KlychTheme.alertRed),
      );
    }
  }

  Future<void> _openGroup(Map<String, dynamic> group) async {
    final groupId = group['id']?.toString();
    if (groupId == null) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => GroupDetailsScreen(groupId: groupId)),
    );

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ГРУПИ'),
        actions: [
          IconButton(
            onPressed: _createGroup,
            icon: const Icon(Icons.add),
            tooltip: 'Створити групу',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: KlychTheme.accent,
              child: groups.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 120),
                        KlychEmptyState(message: 'Немає груп'),
                      ],
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(KlychTheme.spaceLg),
                      itemCount: groups.length,
                      itemBuilder: (_, i) {
                        final group = groups[i];
                        final name = group['name']?.toString() ?? '—';
                        final members = group['group_members'] as List? ?? [];

                        return KlychCard(
                          onTap: () => _openGroup(group),
                          padding: const EdgeInsets.symmetric(
                            horizontal: KlychTheme.spaceLg,
                            vertical: KlychTheme.spaceMd,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$name (${members.length})',
                                  style: KlychTheme.titleMedium.copyWith(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: KlychTheme.textMuted),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
