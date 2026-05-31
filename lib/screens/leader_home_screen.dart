import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/alert_constants.dart';
import '../models/alert_targeting.dart';
import '../models/user_role.dart';
import '../services/alert_service.dart';
import '../utils/alert_utils.dart';
import '../utils/alert_delivery_tracker.dart';
import 'alert_screen.dart';
import 'start_screen.dart';

class LeaderHomeScreen extends StatefulWidget {
  const LeaderHomeScreen({super.key});

  @override
  State<LeaderHomeScreen> createState() => _LeaderHomeScreenState();
}

class _LeaderHomeScreenState extends State<LeaderHomeScreen> {
  final AssetsAudioPlayer player = AssetsAudioPlayer();
  final TextEditingController alertMessageController = TextEditingController();

  RealtimeChannel? channel;

  String callsign = 'LEADER';
  String organization = 'KLYCH';
  String? organizationId;

  bool connected = false;
  bool loading = true;
  bool sending = false;

  String selectedLevel = AlertLevel.red;
  String selectedTarget = AlertTarget.organization;

  List<Map<String, dynamic>> alerts = [];

  final AlertDeliveryTracker _deliveryTracker = AlertDeliveryTracker();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await loadUser();
    await loadLocalAlerts();
    subscribeAlerts();
    if (mounted) setState(() => loading = false);
  }

  Future<void> loadUser() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', user.id)
          .single();

      organizationId = userData['organization_id']?.toString();

      final org = await supabase
          .from('organizations')
          .select('name')
          .eq('id', organizationId!)
          .single();

      if (!mounted) return;

      setState(() {
        callsign = userData['callsign'] ?? 'LEADER';
        organization = org['name'] ?? 'KLYCH';
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> loadLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alertsJson = prefs.getString('leader_alerts_history');
      if (alertsJson == null) return;

      setState(() {
        alerts = List<Map<String, dynamic>>.from(jsonDecode(alertsJson));
      });
      _deliveryTracker.seedFromHistory(alerts);
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> saveLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('leader_alerts_history', jsonEncode(alerts));
    } catch (e) {
      debugPrint('$e');
    }
  }

  void subscribeAlerts() {
    if (organizationId == null) return;

    channel?.unsubscribe();

    final orgId = organizationId!;

    channel = supabase.channel('leader-alerts-$orgId');

    channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_id',
            value: orgId,
          ),
          callback: (payload) async {
            await _handleIncomingAlert(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
          if (!mounted) return;
          setState(() {
            connected = status == RealtimeSubscribeStatus.subscribed;
          });
        });
  }

  Future<void> _addAlertToHistory(Map<String, dynamic> data) async {
    alerts.insert(0, data);
    await saveLocalAlerts();
    if (mounted) setState(() {});
  }

  Future<void> _handleIncomingAlert(Map<String, dynamic> data) async {
    if (organizationId == null) return;
    if (!_deliveryTracker.tryMarkProcessed(data)) return;
    if (!AlertUtils.shouldReceiveAlert(data, organizationId!)) {
      return;
    }

    await _addAlertToHistory(data);

    final authUserId = supabase.auth.currentUser?.id;
    if (AlertDeliveryTracker.isOwnAlert(data, authUserId)) return;

    if (AlertUtils.isRedAlert(data['type']?.toString())) {
      await _triggerRedAlert(data);
    } else {
      _showGreenNotification(data);
    }
  }

  Future<void> _triggerRedAlert(Map<String, dynamic> alert) async {
    try {
      await player.open(
        Audio('assets/alarm.mp3'),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 0);
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AlertScreen(alert: alert, player: player),
        ),
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _showGreenNotification(Map<String, dynamic> alert) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade900,
        content: Text(alert['message']?.toString() ?? 'Інформаційне повідомлення'),
      ),
    );
  }

  Future<void> sendAlert() async {
    if (organizationId == null || sending) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final messageText = alertMessageController.text.trim();
    final message = messageText.isEmpty
        ? AlertService.defaultMessage(selectedLevel)
        : messageText;

    try {
      setState(() => sending = true);

      final inserted = await AlertService.createAlert(
        organizationId: organizationId!,
        message: message,
        level: selectedLevel,
        target: selectedTarget,
        createdByAuthId: user.id,
        createdByName: callsign,
      );

      if (_deliveryTracker.tryMarkProcessed(inserted)) {
        await _addAlertToHistory(inserted);
      }

      alertMessageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Оповіщення надіслано')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'ВИЙТИ З СИСТЕМИ?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Для повторного доступу знадобиться новий код запрошення.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('СКАСУВАТИ', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ВИЙТИ',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  String formatTime(String? value) {
    if (value == null) return '--:--';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '--:--';
    }
  }

  String formatDate(String? value) {
    if (value == null) return '--.--.----';
    try {
      return DateFormat('dd.MM.yyyy').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '--.--.----';
    }
  }

  @override
  void dispose() {
    channel?.unsubscribe();
    player.dispose();
    alertMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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
                      Row(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade800,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.star_rounded, color: Colors.white),
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
                                    fontSize:  28,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  organization,
                                  style: const TextStyle(color: Colors.white54),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: logout,
                            icon: const Icon(Icons.logout, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
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
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 5,
                                  backgroundColor:
                                      connected ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  connected ? 'SYSTEM ACTIVE' : 'SYSTEM OFFLINE',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    letterSpacing: 1.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(
                              callsign.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              UserRole.leader.toUpperCase(),
                              style: TextStyle(
                                color: Colors.orange.shade400,
                                fontSize: 16,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: alertMessageController,
                        maxLines: 2,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Текст оповіщення...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF1A1A1C),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _dropdown(
                        label: 'Рівень',
                        value: selectedLevel,
                        items: AlertLevel.labels,
                        onChanged: (v) => setState(() => selectedLevel = v!),
                      ),
                      const SizedBox(height: 10),
                      _dropdown(
                        label: 'Ціль',
                        value: selectedTarget,
                        items: AlertTarget.labels,
                        onChanged: (v) => setState(() => selectedTarget = v!),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1C),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          AlertTargeting.disabledNotice,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (AlertTargeting.isNonDefaultTarget(selectedTarget)) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade900.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.orange.shade700.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: Colors.orange.shade400,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AlertTargeting.orgWideFallbackWarning,
                                  style: TextStyle(
                                    color: Colors.orange.shade200,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: sending ? null : sendAlert,
                          icon: const Icon(Icons.send_rounded, color: Colors.white),
                          label: Text(
                            sending ? 'НАДСИЛАННЯ...' : 'НАДІСЛАТИ ОПОВІЩЕННЯ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: selectedLevel == AlertLevel.red
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'ОСТАННІ ОПОВІЩЕННЯ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: alerts.isEmpty
                            ? const Center(
                                child: Text(
                                  'Немає активності',
                                  style: TextStyle(color: Colors.white38),
                                ),
                              )
                            : ListView.builder(
                                itemCount: alerts.length,
                                itemBuilder: (_, index) {
                                  final alert = alerts[index];
                                  final level = AlertUtils.levelLabel(
                                    alert['type']?.toString(),
                                  );
                                  final isGreen = level == AlertLevel.green;

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A1A1C),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          alert['message'] ?? 'ALERT',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '$level · ${AlertUtils.targetLabel(alert['target']?.toString())} · ${formatDate(alert['created_at'])} ${formatTime(alert['created_at'])}',
                                          style: TextStyle(
                                            color: isGreen
                                                ? Colors.green.shade400
                                                : Colors.red.shade300,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required String value,
    required Map<String, String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: BorderRadius.circular(18),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1C),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white54),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          hint: Text(label, style: const TextStyle(color: Colors.white54)),
          items: items.entries
              .map(
                (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
