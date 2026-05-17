import 'package:flutter/material.dart';

import 'invite_join_screen.dart';
import 'login_screen.dart';

class JoinServerScreen extends StatelessWidget {
  const JoinServerScreen({super.key});

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
                'ПІДКЛЮЧЕННЯ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 50),

              SizedBox(
                width: double.infinity,
                height: 64,

                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),

                  child: const Text(
                    'УВІЙТИ В АКАУНТ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 64,

                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const InviteJoinScreen(),
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
                    'КОД-ЗАПРОШЕННЯ',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
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
