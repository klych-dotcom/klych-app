import 'package:flutter/material.dart';

import '../main.dart';
import 'home_screen.dart';

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

  Future<void> register() async {
    try {
      setState(() {
        loading = true;
      });

      final authResponse = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = authResponse.user;

      if (user == null) {
        throw Exception('Не вдалося створити акаунт');
      }

      final organization = await supabase
          .from('organizations')
          .insert({
            'name': organizationController.text.trim(),
            'owner_id': user.id,
          })
          .select()
          .single();

      await supabase.from('users').insert({
        'auth_id': user.id,
        'organization_id': organization['id'],
        'name': 'ADMIN',
        'callsign': 'ADMIN',
        'role': 'admin',
        'permission': 'admin',
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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

              const SizedBox(height: 20),

              const Text(
                'СТВОРЕННЯ\nСЕРВЕРА',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                ),
              ),

              const SizedBox(height: 50),

              TextField(
                controller: organizationController,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Назва організації'),
              ),

              const SizedBox(height: 18),

              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Email'),
              ),

              const SizedBox(height: 18),

              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: inputStyle('Пароль'),
              ),

              const SizedBox(height: 34),

              SizedBox(
                width: double.infinity,
                height: 66,

                child: ElevatedButton(
                  onPressed: loading ? null : register,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'СТВОРИТИ',
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
