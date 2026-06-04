import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../utils/auth_error_messages.dart';
import '../models/user_role.dart';
import '../navigation/role_navigation.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'join_server_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> login() async {
    // Валідація порожніх полів перед запитом до мережі
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showSnackBar('Заповніть усі поля');
      return;
    }

    try {
      setState(() {
        loading = true;
      });

      // Авторизація через Supabase Auth
      final AuthResponse res = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = res.user;
      if (user == null) throw Exception('Користувача не знайдено');

      final userData = await supabase
          .from('users')
          .select('role')
          .eq('auth_id', user.id)
          .single();

      if (!mounted) return;

      navigateToRoleHome(context, UserRole.authorizationRole(userData));
    } catch (e) {
      if (!mounted) return;
      // Гарне виведення помилки (наприклад, якщо неправильний пароль)
      _showSnackBar(AuthErrorMessages.from(e));

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

  InputDecoration field(String text) {
    return InputDecoration(
      hintText: text,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF1A1A1C),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
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
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'ВХІД',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 50),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: field('Email'),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: field('Пароль'),
              ),
              const SizedBox(height: 34),
              KlychPrimaryButton(
                label: 'УВІЙТИ',
                icon: Icons.login,
                loading: loading,
                onPressed: loading ? null : login,
                color: KlychTheme.alertRed,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
