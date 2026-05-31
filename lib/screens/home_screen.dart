import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';

import '../main.dart';
import '../models/alert_constants.dart';
import '../models/user_role.dart';
import '../services/alert_service.dart';
import 'start_screen.dart';
import 'users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String organizationName = 'KLYCH SERVER';
  String memberInviteCode = '------';
  String leaderInviteCode = '------';
  String? organizationId;

  bool loading = true;
  bool regeneratingMemberCode = false;
  bool regeneratingLeaderCode = false;

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

      // INVITES (member + leader)
      await _loadInvites();
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

  Future<String> _createInvite(String permission) async {
    final random = Random();
    final code = (100000 + random.nextInt(900000)).toString();

    await supabase.from('invites').insert({
      'organization_id': organizationId,
      'code': code,
      'permission': permission,
    });

    return code;
  }

  Future<void> _loadInvites() async {
    if (organizationId == null) return;

    final rows = await supabase
        .from('invites')
        .select()
        .eq('organization_id', organizationId!);

    String? memberCode;
    String? leaderCode;

    for (final row in rows) {
      final permission =
          (row['permission'] ?? UserRole.member).toString().toLowerCase();
      if (permission == UserRole.leader) {
        leaderCode = row['code']?.toString();
      } else {
        memberCode ??= row['code']?.toString();
      }
    }

    memberCode ??= await _createInvite(UserRole.member);
    leaderCode ??= await _createInvite(UserRole.leader);

    if (!mounted) return;

    setState(() {
      memberInviteCode = memberCode!;
      leaderInviteCode = leaderCode!;
    });
  }

  Future<void> regenerateInviteCode(String permission) async {
    if (organizationId == null) return;

    final isLeader = permission == UserRole.leader;

    try {
      setState(() {
        if (isLeader) {
          regeneratingLeaderCode = true;
        } else {
          regeneratingMemberCode = true;
        }
      });

      final random = Random();
      final newCode = (100000 + random.nextInt(900000)).toString();

      await supabase
          .from('invites')
          .update({'code': newCode})
          .eq('organization_id', organizationId!)
          .eq('permission', permission);

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        if (isLeader) {
          leaderInviteCode = newCode;
        } else {
          memberInviteCode = newCode;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isLeader
                ? 'Код командира оновлено'
                : 'Код учасника оновлено',
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Не вдалося оновити код: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isLeader) {
            regeneratingLeaderCode = false;
          } else {
            regeneratingMemberCode = false;
          }
        });
      }
    }
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Код скопійовано')),
    );
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
          ? AlertService.defaultMessage(AlertLevel.red)
          : messageText;

      await AlertService.createAlert(
        organizationId: organizationId!,
        message: alertMessage,
        level: AlertLevel.red,
        target: AlertTarget.organization,
        createdByAuthId: user.id,
        createdByName: 'ADMIN',
      );

      // AUDIO
      await player.open(
        Audio("assets/alarm.mp3"),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      // VIBRATION
      final hasVibrator = await Vibration.hasVibrator();

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

  Widget _inviteCard({
    required String title,
    required String code,
    required bool regenerating,
    required VoidCallback onCopy,
    required VoidCallback onRefresh,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white38,
              letterSpacing: 2,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, color: Colors.white54),
              ),
              AnimatedRotation(
                turns: regenerating ? 0.5 : 0,
                duration: const Duration(milliseconds: 500),
                child: IconButton(
                  onPressed: regenerating ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
                ),
              ),
            ],
          ),
        ],
      ),
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

                      _inviteCard(
                        title: 'КОД УЧАСНИКА',
                        code: memberInviteCode,
                        regenerating: regeneratingMemberCode,
                        onCopy: () => _copyCode(memberInviteCode),
                        onRefresh: () =>
                            regenerateInviteCode(UserRole.member),
                      ),

                      const SizedBox(height: 16),

                      _inviteCard(
                        title: 'КОД КОМАНДИРА',
                        code: leaderInviteCode,
                        regenerating: regeneratingLeaderCode,
                        onCopy: () => _copyCode(leaderInviteCode),
                        onRefresh: () =>
                            regenerateInviteCode(UserRole.leader),
                      ),

                      const SizedBox(height: 24),

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
                            color: Colors.white.withValues(alpha: 0.22),
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
