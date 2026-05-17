import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/home_screen.dart';
import 'screens/member_home_screen.dart';
import 'screens/start_screen.dart';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://cuoltgakafetqypsvasl.supabase.co',
    anonKey: 'sb_publishable_83R191bduf1U7tDPNqkF9g_cgZb0Z7i',
  );

  // LOCK VERTICAL ORIENTATION
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const AlertApp());
}

class AlertApp extends StatelessWidget {
  const AlertApp({super.key});

  Future<Widget> getStartScreen() async {
    final session = supabase.auth.currentSession;

    // NOT LOGGED IN
    if (session == null) {
      return const StartScreen();
    }

    try {
      final user = supabase.auth.currentUser;

      if (user == null) {
        return const StartScreen();
      }

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', user.id)
          .single();

      final role = userData['role'];

      // ADMIN / LEADER
      if (role == 'admin' || role == 'leader') {
        return const HomeScreen();
      }

      // MEMBER
      return const MemberHomeScreen();
    } catch (e) {
      return const StartScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'KLYCH',

      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F10),
        fontFamily: 'SF Pro Display',
      ),

      home: FutureBuilder<Widget>(
        future: getStartScreen(),

        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F0F10),

              body: Center(child: CircularProgressIndicator(color: Colors.red)),
            );
          }

          return snapshot.data!;
        },
      ),
    );
  }
}
