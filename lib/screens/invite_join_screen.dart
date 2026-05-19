import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'member_home_screen.dart';

class InviteJoinScreen extends StatefulWidget {
  const InviteJoinScreen({super.key});

  @override
  State<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends State<InviteJoinScreen> {
  final inviteController = TextEditingController();
  final callsignController = TextEditingController();
  final passwordController = TextEditingController();

  String selectedRole =
      'member'; // Змінив назву змінної, щоб не плутати з колонками
  bool loading = false;

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
      // повернули поле 'role'
      await supabase.from('users').insert({
        'auth_id': user.id,
        'callsign': callsign,
        'role': selectedRole,
        'permission': selectedRole,
        'organization_id': invite['organization_id'],
        // 'name': callsign, // Якщо захочеш дублювати позивний в поле name, розкоментуй цей рядок
      });

      if (!mounted) return;

      // 5. Успішний перехід на головний екран бійця
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MemberHomeScreen()),
        (route) => false,
      );
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
                  Navigator.pop(context);
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
              const SizedBox(height: 18),

              // Вибір ролі (permission)
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
                    value: selectedRole,
                    dropdownColor: const Color(0xFF1A1A1C),
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white54,
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    items: const [
                      DropdownMenuItem(
                        value: 'member',
                        child: Text('Учасник (Member)'),
                      ),
                      DropdownMenuItem(
                        value: 'driver',
                        child: Text('Водій (Driver)'),
                      ),
                      DropdownMenuItem(
                        value: 'medic',
                        child: Text('Медик (Medic)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedRole = value;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 34),

              SizedBox(
                width: double.infinity,
                height: 66,
                child: ElevatedButton(
                  onPressed: loading ? null : join,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.red.shade900.withOpacity(
                      0.4,
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
