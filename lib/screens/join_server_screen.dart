import 'package:flutter/material.dart';

import 'invite_join_screen.dart';
import 'login_screen.dart';
import 'start_screen.dart';

class JoinServerScreen extends StatelessWidget {
  const JoinServerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },

      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F10),

        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),

            child: Column(
              children: [
                // BACK BUTTON
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
                            builder: (_) => const StartScreen(),
                          ),
                        );
                      }
                    },

                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),

                const Spacer(),

                // LOGO
                Container(
                  width: 92,
                  height: 92,

                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),

                  child: const Icon(
                    Icons.warning_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),

                const SizedBox(height: 34),

                // TITLE
                const Text(
                  'ПІДКЛЮЧЕННЯ',

                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'Оберіть спосіб входу до системи KLYCH',

                  textAlign: TextAlign.center,

                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    height: 1.4,
                  ),
                ),

                const SizedBox(height: 56),

                // LOGIN BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 64,

                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      );
                    },

                    icon: const Icon(Icons.shield_rounded, color: Colors.white),

                    label: const Text(
                      'УВІЙТИ В АКАУНТ',

                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,

                      elevation: 0,

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // INVITE BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 64,

                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const InviteJoinScreen(),
                        ),
                      );
                    },

                    icon: const Icon(Icons.key_rounded, color: Colors.white70),

                    label: const Text(
                      'КОД-ЗАПРОШЕННЯ',

                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white12),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // FOOTER
                Text(
                  'KLYCH Emergency System',

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.18),
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
