import 'package:flutter/material.dart';

import '../main.dart';
import '../models/user_role.dart';
import '../services/department_service.dart';
import '../utils/department_labels.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import '../widgets/org_user_widgets.dart';

class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late String selectedRole;
  String? selectedDepartmentId;
  List<Map<String, dynamic>> departments = [];
  bool saving = false;
  bool isSelf = false;

  @override
  void initState() {
    super.initState();
    selectedRole = UserRole.authorizationRole(widget.user);
    selectedDepartmentId = widget.user['department_id']?.toString();
    isSelf = widget.user['auth_id']?.toString() ==
        supabase.auth.currentUser?.id;
    _loadDepartments();
  }

  Future<void> _loadDepartments() async {
    final orgId = widget.user['organization_id']?.toString();
    if (orgId == null) return;
    departments = await DepartmentService.fetchActive(orgId);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (isSelf) return;
    setState(() => saving = true);
    try {
      final userId = widget.user['id'].toString();
      await UserOrgService.updateRole(userId: userId, role: selectedRole);
      await UserOrgService.updateDepartment(
        userId: userId,
        departmentId: selectedDepartmentId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red.shade900),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _disable(bool disabled) async {
    if (isSelf) return;
    await UserOrgService.setDisabled(
      userId: widget.user['id'].toString(),
      disabled: disabled,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _remove() async {
    if (isSelf) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Видалити користувача?', style: TextStyle(color: Colors.white)),
        content: const Text('Дію не можна скасувати.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('СКАСУВАТИ')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('ВИДАЛИТИ', style: TextStyle(color: KlychTheme.alertRed))),
        ],
      ),
    );
    if (confirmed != true) return;
    await UserOrgService.removeUser(widget.user['id'].toString());
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KlychTheme.background,
      appBar: AppBar(title: const Text('КОРИСТУВАЧ')),
      body: ListView(
        padding: const EdgeInsets.all(KlychTheme.spaceXl),
        children: [
          UserOrgListTile(user: widget.user),
          if (isSelf)
            Padding(
              padding: const EdgeInsets.only(bottom: KlychTheme.spaceLg),
              child: Text(
                'You cannot modify your own role or remove yourself.',
                style: KlychTheme.bodyMedium.copyWith(color: KlychTheme.statusDeployed),
              ),
            ),
          if (!isSelf) ...[
            Text('ROLE', style: KlychTheme.labelCaps),
            ...UserRole.authorizationRoles.map(
              (role) => RadioListTile<String>(
                value: role,
                groupValue: selectedRole,
                onChanged: (v) => setState(() => selectedRole = v!),
                title: Text(role.toUpperCase(), style: KlychTheme.bodyLarge.copyWith(fontSize: 14)),
                activeColor: KlychTheme.accent,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(height: KlychTheme.spaceMd),
            Text('DEPARTMENT', style: KlychTheme.labelCaps),
            const SizedBox(height: KlychTheme.spaceSm),
            DropdownButtonFormField<String>(
              value: selectedDepartmentId,
              dropdownColor: KlychTheme.surfaceElevated,
              style: KlychTheme.bodyLarge.copyWith(fontSize: 14),
              items: departments
                  .map(
                    (d) => DropdownMenuItem(
                      value: d['id'].toString(),
                      child: Text(DepartmentLabels.localize(d['name']?.toString())),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => selectedDepartmentId = v),
            ),
            const SizedBox(height: KlychTheme.spaceXl),
            KlychPrimaryButton(
              label: saving ? 'ЗБЕРЕЖЕННЯ...' : 'ЗБЕРЕГТИ',
              icon: Icons.save_outlined,
              loading: saving,
              onPressed: saving ? null : _save,
            ),
            const SizedBox(height: KlychTheme.spaceMd),
            OutlinedButton(
              onPressed: () => _disable(!(widget.user['is_disabled'] == true)),
              child: Text(widget.user['is_disabled'] == true ? 'УВІМКНУТИ' : 'ВИМКНУТИ'),
            ),
            const SizedBox(height: KlychTheme.spaceMd),
            OutlinedButton(
              onPressed: _remove,
              style: OutlinedButton.styleFrom(foregroundColor: KlychTheme.alertRed),
              child: const Text('ВИДАЛИТИ КОРИСТУВАЧА'),
            ),
          ],
        ],
      ),
    );
  }
}
