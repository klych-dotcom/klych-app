import 'package:flutter/material.dart';

import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'create_server_screen.dart';
import 'join_server_screen.dart';

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Логотип системи оповіщення
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.white,
                  size: 58,
                ),
              ),
              const SizedBox(height: 38),

              // Назва додатку
              const Text(
                'KLYCH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),

              const Text(
                'Emergency Alert System',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
              const SizedBox(height: 70),

              // Кнопка: Створити сервер
              KlychPrimaryButton(
                label: 'СТВОРИТИ СЕРВЕР',
                icon: Icons.dns_outlined,
                color: KlychTheme.alertRed,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateServerScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // Кнопка: Підключитись
              SizedBox(
                width: double.infinity,
                height: 64,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const JoinServerScreen(),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'ПІДКЛЮЧИТИСЬ',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
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
