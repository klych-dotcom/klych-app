import 'package:flutter/material.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';

import '../main.dart';
import 'start_screen.dart';

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

  @override
  void initState() {
    super.initState();

    loadUser();

    loadHistory();

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

  Future<void> loadHistory() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', user.id)
          .single();

      final organizationId = userData['organization_id'];

      final yesterday = DateTime.now()
          .subtract(const Duration(hours: 24))
          .toIso8601String();

      final history = await supabase
          .from('alerts')
          .select()
          .eq('organization_id', organizationId)
          .gte('created_at', yesterday)
          .order('created_at', ascending: false)
          .limit(30);

      setState(() {
        alerts = List<Map<String, dynamic>>.from(history);
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

            alerts.insert(0, data);

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

  void clearHistory() {
    setState(() {
      alerts.clear();
    });
  }

  Future<void> logout() async {
    await supabase.auth.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const StartScreen()),
      (route) => false,
    );
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
                    'ОСТАННІ ТРИВОГИ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  TextButton.icon(
                    onPressed: clearHistory,

                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.white38,
                      size: 18,
                    ),

                    label: const Text(
                      'Очистити',
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

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

                                      const SizedBox(height: 4),

                                      Text(
                                        alert['type'] ?? '',

                                        style: const TextStyle(
                                          color: Colors.white54,
                                        ),
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

class AlertScreen extends StatelessWidget {
  final Map<String, dynamic> alert;

  final AssetsAudioPlayer player;

  const AlertScreen({super.key, required this.alert, required this.player});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 120),

              const SizedBox(height: 40),

              const Text(
                'ТРИВОГА',
                textAlign: TextAlign.center,

                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                alert['message'] ?? 'ALERT',

                textAlign: TextAlign.center,

                style: const TextStyle(color: Colors.white, fontSize: 24),
              ),

              const SizedBox(height: 20),

              Text(
                'ТИП: ${alert['type'] ?? 'GENERAL'}',

                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),

              const SizedBox(height: 12),

              Text(
                'ВІД: ${alert['created_by_name'] ?? 'ADMIN'}',

                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),

              const SizedBox(height: 60),

              SizedBox(
                width: double.infinity,
                height: 72,

                child: ElevatedButton(
                  onPressed: () async {
                    await player.stop();

                    Vibration.cancel();

                    if (!context.mounted) return;

                    Navigator.pop(context);
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),

                  child: const Text(
                    'ПІДТВЕРДИТИ ОТРИМАННЯ',

                    style: TextStyle(
                      color: Colors.black,
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
