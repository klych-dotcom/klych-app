import 'package:flutter/material.dart';

import '../main.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;

  Future<void> login() async {
    try {
      setState(() {
        loading = true;
      });

      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

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

  InputDecoration field(String text) {
    return InputDecoration(
      hintText: text,
      hintStyle: const TextStyle(color: Colors.white38),
      filled: true,
      fillColor: const Color(0xFF1A1A1C),
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
                    Navigator.pop(context);
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
                ),
              ),

              const SizedBox(height: 50),

              TextField(
                controller: emailController,
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

              SizedBox(
                width: double.infinity,
                height: 64,

                child: ElevatedButton(
                  onPressed: loading ? null : login,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  child: loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'УВІЙТИ',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
