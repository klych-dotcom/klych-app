import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/auth_error_messages.dart';
import '../models/user_role.dart';
import '../models/user_status.dart';
import '../navigation/role_navigation.dart';
import '../services/department_service.dart';
import '../utils/department_labels.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'join_server_screen.dart';

class InviteJoinScreen extends StatefulWidget {
  const InviteJoinScreen({super.key});

  @override
  State<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends State<InviteJoinScreen> {
  final inviteController = TextEditingController();
  final callsignController = TextEditingController();
  final passwordController = TextEditingController();

  String? selectedDepartmentId;
  List<Map<String, dynamic>> departments = [];
  bool loading = false;
  bool isLeaderInvite = false;

  @override
  void initState() {
    super.initState();
    inviteController.addListener(_onInviteCodeChanged);
  }

  @override
  void dispose() {
    inviteController.removeListener(_onInviteCodeChanged);
    inviteController.dispose();
    callsignController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _onInviteCodeChanged() {
    _checkInviteType();
  }

  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF1A1A1C),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  void _assertInviteValid(Map<String, dynamic> invite) {
    if (invite['revoked_at'] != null) {
      throw Exception('Код запрошення скасовано');
    }

    final expiresAt = DateTime.tryParse(invite['expires_at']?.toString() ?? '');
    if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
      throw Exception('Код запрошення прострочений');
    }

    final useCount = (invite['use_count'] as num?)?.toInt() ?? 0;
    final maxUses = (invite['max_uses'] as num?)?.toInt() ?? 1;
    if (useCount >= maxUses) {
      throw Exception('Код запрошення вичерпано');
    }
  }

  Future<void> _checkInviteType() async {
    final code = inviteController.text.trim();
    if (code.isEmpty) {
      setState(() {
        isLeaderInvite = false;
        departments = [];
        selectedDepartmentId = null;
      });
      return;
    }

    try {
      final invite = await supabase
          .from('invites')
          .select('role, organization_id, revoked_at, expires_at, use_count, max_uses')
          .eq('code', code)
          .maybeSingle();

      if (!mounted) return;

      if (invite == null) {
        setState(() {
          isLeaderInvite = false;
          departments = [];
          selectedDepartmentId = null;
        });
        return;
      }

      _assertInviteValid(invite);

      final deptList = await DepartmentService.fetchActive(
        invite['organization_id'].toString(),
      );

      setState(() {
        isLeaderInvite =
            (invite['role'] ?? '').toString().toLowerCase() == UserRole.leader;
        departments = deptList;
        selectedDepartmentId = isLeaderInvite
            ? null
            : (deptList.isNotEmpty ? deptList.first['id']?.toString() : null);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          isLeaderInvite = false;
          departments = [];
          selectedDepartmentId = null;
        });
      }
    }
  }

  Future<void> join() async {
    final inviteCode = inviteController.text.trim();
    final callsign = callsignController.text.trim();
    final password = passwordController.text.trim();

    if (inviteCode.isEmpty || callsign.isEmpty || password.isEmpty) {
      _showSnackBar('Заповніть усі поля');
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Пароль має бути не менше 6 символів');
      return;
    }

    if (!isLeaderInvite && selectedDepartmentId == null) {
      _showSnackBar('Оберіть підрозділ');
      return;
    }

    try {
      setState(() => loading = true);

      final invite = await supabase
          .from('invites')
          .select()
          .eq('code', inviteCode)
          .maybeSingle();

      if (invite == null) {
        throw Exception('Код запрошення не знайдено');
      }

      _assertInviteValid(invite);

      final inviteRole =
          (invite['role'] ?? UserRole.member).toString().toLowerCase();

      final assignedRole = inviteRole == UserRole.leader
          ? UserRole.leader
          : UserRole.member;

      final fakeEmail = '${DateTime.now().millisecondsSinceEpoch}@klych.local';

      final authResponse = await supabase.auth.signUp(
        email: fakeEmail,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Не вдалося створити акаунт в системі Auth');
      }

      final profile = await supabase
          .from('users')
          .insert({
            'auth_id': user.id,
            'callsign': callsign,
            ...UserRole.toDbFields(assignedRole),
            'organization_id': invite['organization_id'],
            'department_id': selectedDepartmentId,
            'status': UserStatus.available,
          })
          .select('id')
          .single();

      final newUserId = profile['id'].toString();

      await supabase.from('invite_redemptions').insert({
        'invite_id': invite['id'],
        'user_id': newUserId,
      });

      final useCount = (invite['use_count'] as num?)?.toInt() ?? 0;
      await supabase
          .from('invites')
          .update({'use_count': useCount + 1})
          .eq('id', invite['id']);

      if (!mounted) return;

      navigateToRoleHome(context, assignedRole);
    } catch (e) {
      if (!mounted) return;
      final message = _inviteErrorMessage(e);
      _showSnackBar(message);

      if (mounted) setState(() => loading = false);
    }
  }

  String _inviteErrorMessage(dynamic e) {
    if (e is Exception) {
      final text = e.toString();
      if (text.startsWith('Exception: ')) {
        return text.replaceFirst('Exception: ', '');
      }
    }
    return AuthErrorMessages.from(e);
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const JoinServerScreen(),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              ),
              const SizedBox(height: 30),
              const Text(
                'КОД ДОСТУПУ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 50),
              TextField(
                controller: inviteController,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Код-запрошення'),
                onEditingComplete: _checkInviteType,
              ),
              const SizedBox(height: 18),
              TextField(
                controller: callsignController,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Позивний (наприклад, Хорт)'),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Пароль'),
              ),
              if (isLeaderInvite) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    'Код командира — реєстрація як ${UserRole.leader.toUpperCase()}',
                    style: TextStyle(color: Colors.orange.shade400),
                  ),
                ),
              ] else if (departments.isNotEmpty) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedDepartmentId,
                      dropdownColor: const Color(0xFF1A1A1C),
                      isExpanded: true,
                      hint: const Text(
                        'Підрозділ',
                        style: TextStyle(color: Colors.white54),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      items: departments
                          .map(
                            (d) => DropdownMenuItem(
                              value: d['id'].toString(),
                              child: Text(DepartmentLabels.localize(d['name']?.toString())),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => selectedDepartmentId = value),
                    ),
                  ),
                ),
              ] else if (inviteController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Завантаження підрозділів...',
                  style: TextStyle(color: Colors.white38),
                ),
              ],
              const SizedBox(height: 34),
              KlychPrimaryButton(
                label: 'ПІДКЛЮЧИТИСЬ',
                icon: Icons.login,
                loading: loading,
                onPressed: loading ? null : join,
                color: KlychTheme.alertRed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
