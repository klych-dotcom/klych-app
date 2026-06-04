import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/auth_error_messages.dart';
import '../models/user_role.dart';
import '../models/user_status.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'home_screen.dart';
import 'start_screen.dart';

class CreateServerScreen extends StatefulWidget {
  const CreateServerScreen({super.key});

  @override
  State<CreateServerScreen> createState() => _CreateServerScreenState();
}

class _CreateServerScreenState extends State<CreateServerScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final organizationController = TextEditingController();

  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    organizationController.dispose();
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

  Future<void> register() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final orgName = organizationController.text.trim();

    // 1. Валідація введення на фронтенді
    if (email.isEmpty || password.isEmpty || orgName.isEmpty) {
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

      // 2. Реєстрація користувача в Supabase Auth
      final authResponse = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('Не вдалося створити акаунт в системі Auth');
      }

      // 3. Створення організації в public.organizations
      final organization = await supabase
          .from('organizations')
          .insert({'name': orgName, 'owner_id': user.id})
          .select()
          .single();

      final orgId = organization['id'].toString();

      await supabase.rpc(
        'seed_org_departments',
        params: {'p_org_id': orgId},
      );

      final hq = await supabase
          .from('departments')
          .select('id')
          .eq('organization_id', orgId)
          .eq('name', 'Headquarters')
          .maybeSingle();

      await supabase.from('users').insert({
        'auth_id': user.id,
        'organization_id': organization['id'],
        'callsign': 'ADMIN',
        ...UserRole.toDbFields(UserRole.admin),
        'department_id': hq?['id'],
        'status': UserStatus.available,
      });

      if (!mounted) return;

      // 5. Перехід на головний екран керування (панель адміна)
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
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
              // Кнопка назад
              IconButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const StartScreen()),
                    );
                  }
                },
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              ),
              const SizedBox(height: 20),

              // Заголовок екрана
              const Text(
                'СТВОРЕННЯ\nСЕРВЕРА',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 50),

              // Поле: Назва організації
              TextField(
                controller: organizationController,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Назва організації'),
              ),
              const SizedBox(height: 18),

              // Поле: Email адміна
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Email адміна'),
              ),
              const SizedBox(height: 18),

              // Поле: Пароль сервака
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Пароль'),
              ),
              const SizedBox(height: 34),

              // Кнопка відправки запиту
              KlychPrimaryButton(
                label: 'СТВОРИТИ',
                icon: Icons.add_circle_outline,
                loading: loading,
                onPressed: loading ? null : register,
                color: KlychTheme.alertRed,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
