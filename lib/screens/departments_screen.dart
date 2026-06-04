import 'package:flutter/material.dart';

import '../main.dart';
import '../services/department_service.dart';
import '../utils/db_error_messages.dart';
import '../utils/department_labels.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';

class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key});

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  bool loading = true;
  bool showArchived = true;
  String? organizationId;
  List<Map<String, dynamic>> departments = [];

  List<Map<String, dynamic>> get _activeDepartments =>
      departments.where((d) => d['is_archived'] != true).toList();

  List<Map<String, dynamic>> get _archivedDepartments =>
      departments.where((d) => d['is_archived'] == true).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _load() async {
    setState(() => loading = true);

    try {
      final profile = await supabase
          .from('users')
          .select('organization_id')
          .eq('auth_id', supabase.auth.currentUser!.id)
          .single();

      organizationId = profile['organization_id']?.toString();

      if (organizationId != null) {
        departments = await DepartmentService.fetchAll(organizationId!);
      }
    } catch (e) {
      _showError(DbErrorMessages.from(e, fallback: 'Не вдалося завантажити підрозділи'));
    }

    if (mounted) setState(() => loading = false);
  }

  Future<void> _createDepartment() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Новий підрозділ', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Назва'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('СКАСУВАТИ')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('СТВОРИТИ'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || organizationId == null) return;

    try {
      final created = await DepartmentService.create(
        organizationId: organizationId!,
        name: name,
      );

      _showSuccess('Підрозділ «${created['name']}» збережено');

      await _load();
    } catch (e) {
      _showError(DbErrorMessages.from(e, fallback: e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _renameDepartment(Map<String, dynamic> dept) async {
    if (organizationId == null) return;

    final controller = TextEditingController(text: dept['name']?.toString());
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: const Text('Редагувати', style: TextStyle(color: Colors.white)),
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
      await DepartmentService.rename(
        departmentId: dept['id'].toString(),
        name: name,
        organizationId: organizationId!,
      );
      _showSuccess('Підрозділ перейменовано');
      await _load();
    } catch (e) {
      _showError(DbErrorMessages.from(e, fallback: e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> _archiveDepartment(Map<String, dynamic> dept) async {
    try {
      await DepartmentService.archive(dept['id'].toString());
      _showSuccess('Підрозділ «${dept['name']}» архівовано');
      setState(() => showArchived = true);
      await _load();
    } catch (e) {
      _showError(DbErrorMessages.from(e, fallback: 'Не вдалося архівувати підрозділ'));
    }
  }

  Future<void> _restoreDepartment(Map<String, dynamic> dept) async {
    try {
      await DepartmentService.restore(dept['id'].toString());
      _showSuccess('Підрозділ «${dept['name']}» відновлено');
      await _load();
    } catch (e) {
      _showError(DbErrorMessages.from(e, fallback: 'Не вдалося відновити підрозділ'));
    }
  }

  Widget _departmentTile(Map<String, dynamic> dept, {required bool archived}) {
    return KlychCard(
      padding: const EdgeInsets.symmetric(
        horizontal: KlychTheme.spaceLg,
        vertical: KlychTheme.spaceMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              DepartmentLabels.localize(dept['name']?.toString()),
              style: KlychTheme.titleMedium.copyWith(
                fontSize: 14,
                color: archived ? KlychTheme.textMuted : KlychTheme.textPrimary,
              ),
            ),
          ),
          if (!archived) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54),
              onPressed: () => _renameDepartment(dept),
            ),
            IconButton(
              icon: const Icon(Icons.archive_outlined, color: Colors.white54),
              onPressed: () => _archiveDepartment(dept),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.unarchive_outlined, color: Colors.green),
              tooltip: 'Відновити',
              onPressed: () => _restoreDepartment(dept),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeDepartments;
    final archived = _archivedDepartments;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ПІДРОЗДІЛИ'),
        actions: [
          IconButton(
            onPressed: () => setState(() => showArchived = !showArchived),
            icon: Icon(
              showArchived ? Icons.inventory_2_outlined : Icons.inventory_2,
              color: archived.isEmpty ? Colors.white24 : Colors.white54,
            ),
            tooltip: showArchived ? 'Сховати архів' : 'Показати архів',
          ),
          IconButton(
            onPressed: _createDepartment,
            icon: const Icon(Icons.add, color: Colors.white),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              color: KlychTheme.accent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(KlychTheme.spaceXl),
                children: [
                  Text('АКТИВНІ', style: KlychTheme.labelCaps),
                const SizedBox(height: 12),
                if (active.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Text('Немає активних підрозділів', style: TextStyle(color: Colors.white38)),
                  )
                else
                  ...active.map((dept) => _departmentTile(dept, archived: false)),
                if (showArchived) ...[
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Text(
                        'АРХІВ',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(${archived.length})',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (archived.isEmpty)
                    const Text('Немає архівованих підрозділів', style: TextStyle(color: Colors.white38))
                  else
                    ...archived.map((dept) => _departmentTile(dept, archived: true)),
                ],
                ],
              ),
            ),
    );
  }
}
