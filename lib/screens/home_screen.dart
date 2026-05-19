import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';

import '../main.dart';
import 'start_screen.dart';
import 'users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String organizationName = 'KLYCH SERVER';
  String inviteCode = '------';
  String? organizationId;

  bool loading = true;
  bool regeneratingCode = false;

  final AssetsAudioPlayer player = AssetsAudioPlayer();
  final TextEditingController alertMessageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    player.stop();
    Vibration.cancel();

    player.dispose();
    alertMessageController.dispose();

    super.dispose();
  }

  Future<void> loadData() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      // USER
      final userData = await supabase
          .from('users')
          .select('organization_id')
          .eq('auth_id', user.id)
          .single();

      organizationId = userData['organization_id'];

      // ORGANIZATION
      final organization = await supabase
          .from('organizations')
          .select('name')
          .eq('id', organizationId!)
          .single();

      if (!mounted) return;

      setState(() {
        organizationName = organization['name'];
      });

      // INVITE
      final invite = await supabase
          .from('invites')
          .select('code')
          .eq('organization_id', organizationId!)
          .maybeSingle();

      if (!mounted) return;

      if (invite != null) {
        setState(() {
          inviteCode = invite['code'];
        });
      } else {
        final random = Random();

        final generatedCode = (100000 + random.nextInt(900000)).toString();

        await supabase.from('invites').insert({
          'organization_id': organizationId,
          'code': generatedCode,
          'permission': 'member',
        });

        setState(() {
          inviteCode = generatedCode;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Помилка завантаження даних: $e');
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> regenerateInviteCode() async {
    if (organizationId == null) return;

    try {
      setState(() {
        regeneratingCode = true;
      });

      final random = Random();

      final newCode = (100000 + random.nextInt(900000)).toString();

      await supabase
          .from('invites')
          .update({'code': newCode})
          .eq('organization_id', organizationId!);

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        inviteCode = newCode;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Код-запрошення оновлено')));
    } catch (e) {
      _showErrorSnackBar('Не вдалося оновити код: $e');
    } finally {
      if (mounted) {
        setState(() {
          regeneratingCode = false;
        });
      }
    }
  }

  Future<void> logout() async {
    try {
      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (route) => false,
      );
    } catch (e) {
      _showErrorSnackBar('Помилка виходу: $e');
    }
  }

  Future<void> testAlert() async {
    if (organizationId == null) return;

    try {
      FocusScope.of(context).unfocus();

      final user = supabase.auth.currentUser;

      if (user == null) return;

      final messageText = alertMessageController.text.trim();

      final alertMessage = messageText.isEmpty
          ? '🚨 ТЕСТОВА ТРИВОГА'
          : messageText;

      // SAVE ALERT
      await supabase.from('alerts').insert({
        'organization_id': organizationId,
        'message': alertMessage,
        'type': 'GENERAL',
        'created_by': user.id,
        'created_by_name': 'ADMIN',
      });

      // AUDIO
      await player.open(
        Audio("assets/alarm.mp3"),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      // VIBRATION
      final hasVibrator = await Vibration.hasVibrator() ?? false;

      if (hasVibrator) {
        Vibration.vibrate(
          pattern: [0, 1000, 500, 1000],
          repeat: 0, // Повторюємо патерн постійно, поки не натиснуть "ЗУПИНИТИ"
        );
      }

      if (!mounted) return;

      // ALERT DIALOG
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),

            title: const Row(
              children: [
                Icon(Icons.warning_rounded, color: Colors.red),

                SizedBox(width: 10),

                Text(
                  "ТРИВОГА",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            content: Text(
              alertMessage,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),

            actions: [
              TextButton(
                onPressed: () async {
                  await player.stop();

                  Vibration.cancel();

                  if (!dialogContext.mounted) return;

                  // Закриваємо саме діалогове вікно через його власний context
                  Navigator.pop(dialogContext);

                  alertMessageController.clear();
                },

                child: const Text(
                  "ЗУПИНИТИ",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      _showErrorSnackBar('Помилка активації тривоги: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade900),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },

      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F10),

        body: loading
            ? const Center(child: CircularProgressIndicator(color: Colors.red))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // HEADER
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,

                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(18),
                            ),

                            child: const Icon(
                              Icons.warning_rounded,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(width: 16),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,

                              children: [
                                const Text(
                                  'KLYCH',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),

                                Text(
                                  organizationName,
                                  overflow: TextOverflow.ellipsis,

                                  style: const TextStyle(color: Colors.white54),
                                ),
                              ],
                            ),
                          ),

                          IconButton(
                            onPressed: logout,

                            icon: const Icon(
                              Icons.logout,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 36),

                      // INVITE CARD
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),

                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(28),
                        ),

                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            const Row(
                              children: [
                                CircleAvatar(
                                  radius: 5,
                                  backgroundColor: Colors.green,
                                ),

                                SizedBox(width: 10),

                                Text(
                                  'SYSTEM ACTIVE',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 26),

                            const Text(
                              'INVITE CODE',
                              style: TextStyle(
                                color: Colors.white38,
                                letterSpacing: 2,
                              ),
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    inviteCode,

                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 4,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 10),

                                // COPY
                                IconButton(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: inviteCode),
                                    );

                                    if (!mounted) return;

                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Код скопійовано'),
                                      ),
                                    );
                                  },

                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    color: Colors.white54,
                                  ),
                                ),

                                // REFRESH
                                AnimatedRotation(
                                  turns: regeneratingCode ? 0.5 : 0,

                                  duration: const Duration(milliseconds: 500),

                                  child: IconButton(
                                    onPressed: regeneratingCode
                                        ? null
                                        : regenerateInviteCode,

                                    icon: const Icon(
                                      Icons.refresh_rounded,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ALERT MESSAGE
                      TextField(
                        controller: alertMessageController,

                        maxLines: 3,

                        style: const TextStyle(color: Colors.white),

                        decoration: InputDecoration(
                          hintText: 'Повідомлення до тривоги...',

                          hintStyle: const TextStyle(color: Colors.white38),

                          filled: true,
                          fillColor: const Color(0xFF1A1A1C),

                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),

                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),

                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ALERT BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 64,

                        child: ElevatedButton.icon(
                          onPressed: testAlert,

                          icon: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                          ),

                          label: const Text(
                            'ТЕСТ ТРИВОГИ',

                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),

                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade700,

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // USERS BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 58,

                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UsersScreen(),
                              ),
                            );
                          },

                          icon: const Icon(
                            Icons.people_alt_rounded,
                            color: Colors.white70,
                          ),

                          label: const Text(
                            'КОРИСТУВАЧІ',

                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white12),

                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),

                      const Spacer(),

                      // FOOTER
                      Center(
                        child: Text(
                          'KLYCH Emergency System',

                          style: TextStyle(
                            color: Colors.white.withOpacity(0.22),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
