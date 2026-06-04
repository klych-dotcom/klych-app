import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';

import '../main.dart';
import '../mixins/alert_realtime_listener.dart';
import '../models/alert_recipients_selection.dart';
import '../models/alert_constants.dart';
import '../models/user_role.dart';
import '../services/alert_service.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'start_screen.dart';
import 'users_screen.dart';
import 'departments_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with AlertRealtimeListener {
  String organizationName = 'KLYCH SERVER';
  String memberInviteCode = '------';
  String leaderInviteCode = '------';
  String? organizationId;
  String? adminUserId;

  bool loading = true;
  bool regeneratingMemberCode = false;
  bool regeneratingLeaderCode = false;

  final TextEditingController alertMessageController = TextEditingController();

  @override
  String? get alertOrganizationId => organizationId;

  @override
  String? get alertCurrentUserId => adminUserId;

  @override
  Future<void> onOrgAlertInserted(Map<String, dynamic> alert) async {}

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    disposeAlertRealtime();
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
          .select('organization_id, id')
          .eq('auth_id', user.id)
          .single();

      organizationId = userData['organization_id'];
      adminUserId = userData['id']?.toString();

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

      subscribeOrgAlerts('admin-alerts');
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

  static const _inviteLifetime = Duration(days: 30);

  bool _isInviteActive(Map<String, dynamic> row) {
    if (row['revoked_at'] != null) return false;
    final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');
    if (expiresAt == null || expiresAt.isBefore(DateTime.now().toUtc())) {
      return false;
    }
    final useCount = (row['use_count'] as num?)?.toInt() ?? 0;
    final maxUses = (row['max_uses'] as num?)?.toInt() ?? 1;
    return useCount < maxUses;
  }

  Future<String> _createInvite(String role) async {
    final random = Random();
    final code = (100000 + random.nextInt(900000)).toString();
    final expiresAt = DateTime.now().toUtc().add(_inviteLifetime);

    await supabase.from('invites').insert({
      'organization_id': organizationId,
      'code': code,
      'role': role,
      'expires_at': expiresAt.toIso8601String(),
      'max_uses': role == UserRole.leader ? 10 : 100,
      if (adminUserId != null) 'created_by': adminUserId,
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

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      if (!_isInviteActive(row)) continue;
      final role = (row['role'] ?? UserRole.member).toString().toLowerCase();
      if (role == UserRole.leader) {
        leaderCode ??= row['code']?.toString();
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

  Future<void> regenerateInviteCode(String role) async {
    if (organizationId == null) return;

    final isLeader = role == UserRole.leader;

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

      final rows = await supabase
          .from('invites')
          .select()
          .eq('organization_id', organizationId!)
          .eq('role', role);

      Map<String, dynamic>? activeInvite;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        if (_isInviteActive(row)) {
          activeInvite = row;
          break;
        }
      }

      if (activeInvite != null) {
        await supabase
            .from('invites')
            .update({'code': newCode})
            .eq('id', activeInvite['id']);
      } else {
        await _createInvite(role);
        if (!mounted) return;
        await _loadInvites();
        return;
      }

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

      final senderUserId = await UserOrgService.currentUserId();
      if (senderUserId == null) return;

      await AlertService.createAlert(
        organizationId: organizationId!,
        message: alertMessage,
        level: AlertLevel.red,
        recipients: AlertRecipientsSelection(),
        senderUserId: senderUserId,
        isTest: true,
      );

      // AUDIO — local test feedback for admin-initiated org-wide test
      final player = getOrCreatePlayer();
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
                  final player = getOrCreatePlayer();
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
    return KlychCard(
      padding: const EdgeInsets.all(KlychTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KlychTheme.labelCaps),
          const SizedBox(height: KlychTheme.spaceSm),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: KlychTheme.titleMedium.copyWith(
                    fontSize: 22,
                    letterSpacing: 2,
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, color: KlychTheme.textSecondary),
              ),
              AnimatedRotation(
                turns: regenerating ? 0.5 : 0,
                duration: const Duration(milliseconds: 500),
                child: IconButton(
                  onPressed: regenerating ? null : onRefresh,
                  icon: const Icon(Icons.refresh_rounded, color: KlychTheme.textSecondary),
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
        backgroundColor: KlychTheme.background,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      // HEADER
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: KlychAppHeader(
                              organization: organizationName,
                              callsign: 'ADMIN',
                            ),
                          ),
                          IconButton(
                            onPressed: logout,
                            icon: const Icon(Icons.logout, color: KlychTheme.textSecondary),
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
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Повідомлення до тривоги...',
                        ),
                      ),

                      const SizedBox(height: KlychTheme.spaceMd),

                      KlychPrimaryButton(
                        label: 'ТЕСТ ТРИВОГИ',
                        icon: Icons.notifications_active_rounded,
                        onPressed: testAlert,
                        color: KlychTheme.alertRed,
                      ),

                      const SizedBox(height: KlychTheme.spaceSm),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UsersScreen(adminMode: true),
                              ),
                            );
                          },
                          icon: const Icon(Icons.people_alt_outlined),
                          label: const Text('КОРИСТУВАЧІ'),
                        ),
                      ),

                      const SizedBox(height: KlychTheme.spaceSm),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DepartmentsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.apartment_rounded),
                          label: const Text('ПІДРОЗДІЛИ'),
                        ),
                      ),

                      const SizedBox(height: KlychTheme.spaceXl),

                      Center(
                        child: Text(
                          'KLYCH Emergency System',
                          style: KlychTheme.bodyMedium.copyWith(
                            fontSize: 11,
                            color: KlychTheme.textMuted,
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
