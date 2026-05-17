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

  String role = 'member';

  bool loading = false;

  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),

      filled: true,
      fillColor: const Color(0xFF1A1A1C),

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
    try {
      setState(() {
        loading = true;
      });

      final invite = await supabase
          .from('invites')
          .select()
          .eq('code', inviteController.text.trim())
          .maybeSingle();

      if (invite == null) {
        throw Exception('Код не знайдено');
      }

      final fakeEmail = '${DateTime.now().millisecondsSinceEpoch}@klych.local';

      final authResponse = await supabase.auth.signUp(
        email: fakeEmail,
        password: passwordController.text.trim(),
      );

      final user = authResponse.user;

      if (user == null) {
        throw Exception('Не вдалося створити користувача');
      }

      await supabase.from('users').insert({
        'auth_id': user.id,
        'callsign': callsignController.text.trim(),
        'role': role,
        'permission': role,
        'organization_id': invite['organization_id'],
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MemberHomeScreen()),
        (route) => false,
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }

    setState(() {
      loading = false;
    });
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
                decoration: inputStyle('Позивний'),
              ),

              const SizedBox(height: 18),

              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Пароль'),
              ),

              const SizedBox(height: 18),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18),

                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1C),
                  borderRadius: BorderRadius.circular(18),
                ),

                child: DropdownButton<String>(
                  value: role,
                  dropdownColor: const Color(0xFF1A1A1C),

                  underline: const SizedBox(),
                  isExpanded: true,

                  style: const TextStyle(color: Colors.white, fontSize: 16),

                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Учасник')),
                    DropdownMenuItem(value: 'driver', child: Text('Водій')),
                    DropdownMenuItem(value: 'medic', child: Text('Медик')),
                  ],

                  onChanged: (value) {
                    setState(() {
                      role = value!;
                    });
                  },
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

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'ПІДКЛЮЧИТИСЬ',
                          style: TextStyle(
                            color: Colors.white,
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
