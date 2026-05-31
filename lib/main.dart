import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/user_role.dart';
import 'navigation/role_navigation.dart';
import 'screens/start_screen.dart';

// Глобальний клієнт Supabase для всього додатка
final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ініціалізація Supabase
  await Supabase.initialize(
    url: 'https://cuoltgakafetqypsvasl.supabase.co',
    anonKey: 'sb_publishable_83R191bduf1U7tDPNqkF9g_cgZb0Z7i',
  );

  // Блокування горизонтального режиму (тільки портретна орієнтація)
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const AlertApp());
}

class AlertApp extends StatefulWidget {
  const AlertApp({super.key});

  @override
  State<AlertApp> createState() => _AlertAppState();
}

class _AlertAppState extends State<AlertApp> {
  late final Future<Widget> _initialScreenFuture;

  @override
  void initState() {
    super.initState();
    // Ініціалізуємо Future один раз при старті додатка,
    // щоб уникнути повторних запитів до БД при ребілдах екрана.
    _initialScreenFuture = _getStartScreen();
  }

  Future<Widget> _getStartScreen() async {
    final session = supabase.auth.currentSession;

    // Якщо сесії немає (користувач не залогінений) -> на StartScreen
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
          .select('role, permission')
          .eq('auth_id', user.id)
          .single();

      final role = UserRole.resolve(userData);
      return homeScreenForRole(role);
    } catch (e) {
      // У разі помилки (наприклад, збій мережі чи відсутність запису в users)
      debugPrint('Помилка авторизації в main.dart: $e');
      return const StartScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'KLYCH',

      // Фірмова темна тема для системи оповіщення
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F10),
        fontFamily: 'SF Pro Display',
      ),

      home: FutureBuilder<Widget>(
        future: _initialScreenFuture,
        builder: (context, snapshot) {
          // Поки йде перевірка сесії та запит до Supabase — показуємо лоадер
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              backgroundColor: Color(0xFF0F0F10),
              body: Center(child: CircularProgressIndicator(color: Colors.red)),
            );
          }

          // Повертаємо визначений екран або дефолтний StartScreen, якщо щось пішло не так
          return snapshot.data ?? const StartScreen();
        },
      ),
    );
  }
}
