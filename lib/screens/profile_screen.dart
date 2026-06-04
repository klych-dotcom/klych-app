import 'package:flutter/material.dart';

import '../main.dart';
import '../models/user_role.dart';
import '../models/user_status.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool loading = true;
  bool saving = false;
  Map<String, dynamic>? profile;
  late TextEditingController callsignController;

  @override
  void initState() {
    super.initState();
    callsignController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    callsignController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await UserOrgService.currentUserProfile();
      if (data != null) {
        await UserOrgService.touchLastActivity(data['id'].toString());
        callsignController.text = data['callsign']?.toString() ?? '';
      }
      profile = data;
    } catch (e) {
      debugPrint('$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _saveCallsign() async {
    if (profile == null) return;

    setState(() => saving = true);
    try {
      await UserOrgService.updateCallsign(
        userId: profile!['id'].toString(),
        callsign: callsignController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Позивний збережено')),
        );
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authEmail = supabase.auth.currentUser?.email ?? '—';

    return Scaffold(
      backgroundColor: KlychTheme.background,
      appBar: AppBar(title: const Text('ПРОФІЛЬ')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
          ? const KlychEmptyState(message: 'Профіль не знайдено')
          : Padding(
              padding: const EdgeInsets.all(KlychTheme.space2xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ПОЗИВНИЙ', style: KlychTheme.labelCaps),
                  const SizedBox(height: KlychTheme.spaceMd),
                  TextField(
                    controller: callsignController,
                    style: KlychTheme.bodyLarge,
                  ),
                  const SizedBox(height: KlychTheme.spaceLg),
                  KlychPrimaryButton(
                    label: saving ? 'ЗБЕРЕЖЕННЯ...' : 'ЗБЕРЕГТИ ПОЗИВНИЙ',
                    icon: Icons.save_outlined,
                    loading: saving,
                    onPressed: saving ? null : _saveCallsign,
                  ),
                  const SizedBox(height: KlychTheme.space3xl),
                  Text('ОБЛІКОВИЙ ЗАПИС', style: KlychTheme.labelCaps),
                  const SizedBox(height: KlychTheme.spaceLg),
                  _infoRow('Email', authEmail),
                  _infoRow(
                    'Роль',
                    UserRole.authorizationRole(profile!).toUpperCase(),
                  ),
                  _infoRow(
                    'Підрозділ',
                    UserOrgService.departmentName(profile!),
                  ),
                  _infoRow(
                    'Статус',
                    UserStatus.label(profile!['status']?.toString()),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KlychTheme.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: KlychTheme.bodyMedium),
          ),
          Expanded(
            child: Text(value, style: KlychTheme.bodyLarge.copyWith(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
