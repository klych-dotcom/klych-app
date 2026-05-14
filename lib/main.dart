import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// =========================
// SUPABASE
// =========================

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cuoltgakafetqypsvasl.supabase.co',
    anonKey: 'sb_publishable_83R191bduf1U7tDPNqkF9g_cgZb0Z7i',
  );

  runApp(const AlertApp());
}

// =========================
// APP
// =========================

class AlertApp extends StatelessWidget {
  const AlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: supabase.auth.currentSession == null
          ? const StartScreen()
          : const HomeScreen(),
    );
  }
}

// =========================
// START SCREEN
// =========================

class StartScreen extends StatelessWidget {
  const StartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 100,
              height: 100,

              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(28),
              ),

              child: const Icon(
                Icons.warning_rounded,
                color: Colors.white,
                size: 54,
              ),
            ),

            const SizedBox(height: 30),

            const Text(
              "KLYCH",
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              "Emergency Alert System",
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),

            const SizedBox(height: 60),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CreateServerScreen(),
                    ),
                  );
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),

                child: const Text(
                  "СТВОРИТИ СЕРВЕР",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JoinServerScreen()),
                  );
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1C1C1E),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),

                child: const Text(
                  "ПРИЄДНАТИСЯ",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// CREATE SERVER SCREEN
// =========================

class CreateServerScreen extends StatefulWidget {
  const CreateServerScreen({super.key});

  @override
  State<CreateServerScreen> createState() => _CreateServerScreenState();
}

class _CreateServerScreenState extends State<CreateServerScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final organizationController = TextEditingController();

  bool loading = false;

  Future<void> register() async {
    try {
      setState(() {
        loading = true;
      });

      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = response.user;

      if (user == null) return;

      final organization = await supabase
          .from('organizations')
          .insert({
            'name': organizationController.text.trim(),
            'owner_id': user.id,
          })
          .select()
          .single();

      await supabase.from('users').insert({
        'auth_id': user.id,
        'organization_id': organization['id'],
        'name': 'ADMIN',
        'callsign': 'ADMIN',
        'role': 'admin',
        'permission': 'admin',
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } catch (e) {
      print(e);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }

    setState(() {
      loading = false;
    });
  }

  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),

      filled: true,
      fillColor: const Color(0xFF1C1C1E),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      appBar: AppBar(backgroundColor: const Color(0xFF111111)),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          children: [
            TextField(
              controller: organizationController,
              style: const TextStyle(color: Colors.white),
              decoration: inputStyle("Назва серверу"),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: inputStyle("Email"),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: inputStyle("Password"),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: loading ? null : register,

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),

                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "СТВОРИТИ",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// JOIN SERVER SCREEN
// =========================

class JoinServerScreen extends StatefulWidget {
  const JoinServerScreen({super.key});

  @override
  State<JoinServerScreen> createState() => _JoinServerScreenState();
}

class _JoinServerScreenState extends State<JoinServerScreen> {
  final inviteController = TextEditingController();
  final nameController = TextEditingController();

  String role = "medic";

  bool loading = false;

  Future<void> joinServer() async {
    try {
      setState(() {
        loading = true;
      });

      final invite = await supabase
          .from('invites')
          .select()
          .eq('code', inviteController.text.trim())
          .maybeSingle();

      if (invite == null) {
        throw Exception("Інвайт код не знайдено");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Пізніше додамо повний join flow")),
      );
    } catch (e) {
      print(e);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }

    setState(() {
      loading = false;
    });
  }

  InputDecoration inputStyle(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),

      filled: true,
      fillColor: const Color(0xFF1C1C1E),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      appBar: AppBar(backgroundColor: const Color(0xFF111111)),

      body: Padding(
        padding: const EdgeInsets.all(24),

        child: Column(
          children: [
            TextField(
              controller: inviteController,
              style: const TextStyle(color: Colors.white),
              decoration: inputStyle("Інвайт код"),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: inputStyle("Позивний"),
            ),

            const SizedBox(height: 20),

            DropdownButtonFormField(
              dropdownColor: const Color(0xFF1C1C1E),
              value: role,

              decoration: inputStyle("Роль"),

              items: const [
                DropdownMenuItem(
                  value: "medic",
                  child: Text("Медик", style: TextStyle(color: Colors.white)),
                ),
                DropdownMenuItem(
                  value: "driver",
                  child: Text("Водій", style: TextStyle(color: Colors.white)),
                ),
                DropdownMenuItem(
                  value: "other",
                  child: Text("Інше", style: TextStyle(color: Colors.white)),
                ),
              ],

              onChanged: (value) {
                setState(() {
                  role = value!;
                });
              },
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: loading ? null : joinServer,

                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),

                child: loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        "ПРИЄДНАТИСЯ",
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =========================
// HOME SCREEN
// =========================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final int userId = 1;

  final String serverUrl = "https://klych-server.onrender.com";

  int lastAlertId = 0;

  @override
  void initState() {
    super.initState();

    startPolling();
  }

  void startPolling() {
    initializeLastAlert();

    Timer.periodic(const Duration(seconds: 3), (timer) {
      checkAlerts();
    });
  }

  Future<void> initializeLastAlert() async {
    try {
      final response = await http.get(
        Uri.parse("$serverUrl/alerts?userId=$userId"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          lastAlertId = data.last["id"];
        }
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> checkAlerts() async {
    try {
      final response = await http.get(
        Uri.parse("$serverUrl/alerts?userId=$userId"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data.isNotEmpty) {
          final last = data.last;

          if (last["id"] != lastAlertId) {
            lastAlertId = last["id"];

            if (!mounted) return;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlertScreen(message: last["message"]),
              ),
            );
          }
        }
      }
    } catch (e) {
      print(e);
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),

      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),

        actions: [
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),

      body: const Center(
        child: Text(
          "KLYCH SYSTEM ACTIVE",
          style: TextStyle(color: Colors.white, fontSize: 28),
        ),
      ),
    );
  }
}

// =========================
// ALERT SCREEN
// =========================

class AlertScreen extends StatefulWidget {
  final String message;

  const AlertScreen({super.key, required this.message});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  final AssetsAudioPlayer player = AssetsAudioPlayer();

  @override
  void initState() {
    super.initState();

    playAlarm();
  }

  Future<void> playAlarm() async {
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
    } catch (e) {
      print(e);
    }
  }

  @override
  void dispose() {
    player.stop();
    Vibration.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red,

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,

            children: [
              const Text(
                "🚨 ТРИВОГА",
                style: TextStyle(
                  fontSize: 42,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                widget.message,

                textAlign: TextAlign.center,

                style: const TextStyle(fontSize: 28, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
