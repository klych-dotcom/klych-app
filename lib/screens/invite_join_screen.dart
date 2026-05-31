import 'package:flutter/material.dart';

import '../main.dart';
import '../models/user_role.dart';
import '../navigation/role_navigation.dart';
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

  String selectedCategory = UserRole.member;
  bool loading = false;
  bool isLeaderInvite = false;

  @override
  void dispose() {
    inviteController.dispose();
    callsignController.dispose();
    passwordController.dispose();
    super.dispose();
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

  Future<void> _checkInviteType() async {
    final code = inviteController.text.trim();
    if (code.isEmpty) {
      setState(() => isLeaderInvite = false);
      return;
    }

    try {
      final invite = await supabase
          .from('invites')
          .select('permission')
          .eq('code', code)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        isLeaderInvite =
            (invite?['permission'] ?? '').toString().toLowerCase() ==
            UserRole.leader;
      });
    } catch (_) {
      if (mounted) setState(() => isLeaderInvite = false);
    }
  }

  Future<void> join() async {
    final inviteCode = inviteController.text.trim();
    final callsign = callsignController.text.trim();
    final password = passwordController.text.trim();

    // 1. Валідація введення на фронтенді
    if (inviteCode.isEmpty || callsign.isEmpty || password.isEmpty) {
      _showSnackBar('Заповніть усі поля');
      return;
    }

    if (password.length < 6) {
      _showSnackBar('Пароль має бути не менше 6 символів');
      return;
    }

    try {
      setState(() {
        loading = true;
      });

      // 2. Перевірка коду запрошення в таблиці invites
      final invite = await supabase
          .from('invites')
          .select()
          .eq('code', inviteCode)
          .maybeSingle();

      if (invite == null) {
        throw Exception('Код запрошення не знайдено або застарів');
      }

      final invitePermission =
          (invite['permission'] ?? UserRole.member).toString().toLowerCase();

      final String assignedRole;
      if (invitePermission == UserRole.leader) {
        assignedRole = UserRole.leader;
      } else {
        assignedRole = selectedCategory;
      }

      // Твій крутий лайфхак з фейковим емейлом для простоти входу
      final fakeEmail = '${DateTime.now().millisecondsSinceEpoch}@klych.local';

      // 3. Реєстрація в Supabase Auth
      final authResponse = await supabase.auth.signUp(
        email: fakeEmail,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Не вдалося створити акаунт в системі Auth');
      }

      // 4. Запис профілю у твою таблицю public.users
      await supabase.from('users').insert({
        'auth_id': user.id,
        'callsign': callsign,
        ...UserRole.toDbFields(assignedRole),
        'organization_id': invite['organization_id'],
      });

      if (!mounted) return;

      navigateToRoleHome(context, assignedRole);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(e.toString().replaceAll('Exception: ', ''));

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
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
              ] else ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedCategory,
                      dropdownColor: const Color(0xFF1A1A1C),
                      isExpanded: true,
                      icon: const Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white54,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      items: const [
                        DropdownMenuItem(
                          value: UserRole.member,
                          child: Text('Учасник (Other)'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.driver,
                          child: Text('Водій (Driver)'),
                        ),
                        DropdownMenuItem(
                          value: UserRole.medic,
                          child: Text('Медик (Medic)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => selectedCategory = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 34),

              SizedBox(
                width: double.infinity,
                height: 66,
                child: ElevatedButton(
                  onPressed: loading ? null : join,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.shade900.withValues(
                      alpha: 0.4,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  child: loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'ПІДКЛЮЧИТИСЬ',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
