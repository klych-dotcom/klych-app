import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import 'alert_screen.dart';
import 'join_server_screen.dart';

class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> {
  final AssetsAudioPlayer player = AssetsAudioPlayer();

  RealtimeChannel? channel;

  String callsign = 'MEMBER';
  String role = 'member';
  String organization = 'KLYCH';

  bool connected = true;

  List<Map<String, dynamic>> alerts = [];

  DateTime? clearedAt;

  @override
  void initState() {
    super.initState();

    loadUser();
    loadLocalAlerts();

    subscribeAlerts();
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

      final org = await supabase
          .from('organizations')
          .select()
          .eq('id', userData['organization_id'])
          .single();

      setState(() {
        callsign = userData['callsign'] ?? 'MEMBER';
        role = userData['role'] ?? 'member';
        organization = org['name'] ?? 'KLYCH';
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> loadLocalAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final cleared = prefs.getString('alerts_cleared_at');

      if (cleared != null) {
        clearedAt = DateTime.tryParse(cleared);
      }

      final alertsJson = prefs.getString('alerts_history');

      if (alertsJson == null) return;

      final decoded = jsonDecode(alertsJson);

      final loadedAlerts = List<Map<String, dynamic>>.from(decoded);

      final filteredAlerts = loadedAlerts.where((alert) {
        if (clearedAt == null) return true;

        final createdAt = DateTime.tryParse(alert['created_at'] ?? '');

        if (createdAt == null) return true;

        return createdAt.isAfter(clearedAt!);
      }).toList();

      setState(() {
        alerts = filteredAlerts;
      });
    } catch (e) {
      print(e);
    }
  }

  Future<void> saveAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('alerts_history', jsonEncode(alerts));
    } catch (e) {
      print(e);
    }
  }

  Future<void> clearAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final now = DateTime.now();

      await prefs.setString('alerts_cleared_at', now.toIso8601String());

      await prefs.setString('alerts_history', jsonEncode([]));

      setState(() {
        alerts.clear();
        clearedAt = now;
      });
    } catch (e) {
      print(e);
    }
  }

  void subscribeAlerts() {
    channel = supabase.channel('alerts-channel');

    channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          callback: (payload) async {
            final data = payload.newRecord;

            final createdAt = DateTime.tryParse(data['created_at'] ?? '');

            if (clearedAt != null &&
                createdAt != null &&
                createdAt.isBefore(clearedAt!)) {
              return;
            }

            alerts.insert(0, data);

            await saveAlerts();

            setState(() {});

            await triggerAlarm(data);
          },
        )
        .subscribe();
  }

  Future<void> triggerAlarm(Map<String, dynamic> alert) async {
    try {
      await player.open(
        Audio("assets/alarm.mp3"),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      final hasVibrator = await Vibration.hasVibrator() ?? false;

      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 0);
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AlertScreen(alert: alert, player: player),
        ),
      );
    } catch (e) {
      print(e);
    }
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),

          title: const Text(
            'ВИЙТИ З СИСТЕМИ?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),

          content: const Text(
            'Локальна історія оповіщень буде очищена з пристрою.\n\nДля повторного доступу знадобиться повторна авторизація.',
            style: TextStyle(color: Colors.white70),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text(
                'СКАСУВАТИ',
                style: TextStyle(color: Colors.white54),
              ),
            ),

            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'ВИЙТИ',
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

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('alerts_history');

      await prefs.remove('alerts_cleared_at');

      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const JoinServerScreen()),
        (route) => false,
      );
    } catch (e) {
      print(e);
    }
  }

  String formatTime(String? value) {
    if (value == null) return '--:--';

    try {
      final date = DateTime.parse(value).toLocal();

      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return '--:--';
    }
  }

  @override
  void dispose() {
    channel?.unsubscribe();

    player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),

      body: SafeArea(
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
                          organization,
                          style: const TextStyle(color: Colors.white54),
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

              const SizedBox(height: 34),

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
                          backgroundColor: connected
                              ? Colors.green
                              : Colors.red,
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
                      role.toUpperCase(),

                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              SizedBox(
                width: double.infinity,
                height: 62,

                child: ElevatedButton.icon(
                  onPressed: () async {
                    await triggerAlarm({
                      'type': 'TEST',
                      'message': 'Тест локальної тривоги',
                      'created_by_name': 'LOCAL TEST',
                      'created_at': DateTime.now().toIso8601String(),
                    });
                  },

                  icon: const Icon(Icons.notifications_active),

                  label: const Text(
                    'ЛОКАЛЬНИЙ ТЕСТ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [
                  const Text(
                    'ІСТОРІЯ ОПОВІЩЕНЬ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  IconButton(
                    onPressed: clearAlerts,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

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

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(18),

                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1C),
                              borderRadius: BorderRadius.circular(20),
                            ),

                            child: Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.red,
                                ),

                                const SizedBox(width: 14),

                                Expanded(
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

                                      Row(
                                        children: [
                                          Text(
                                            alert['type'] ?? '',

                                            style: const TextStyle(
                                              color: Colors.white54,
                                            ),
                                          ),

                                          const SizedBox(width: 12),

                                          Text(
                                            formatTime(alert['created_at']),

                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
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
    );
  }
}
