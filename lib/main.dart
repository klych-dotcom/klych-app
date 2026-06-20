import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/user_role.dart';
import 'navigation/role_navigation.dart';
import 'services/push_service.dart';
import 'theme/klych_theme.dart';
import 'screens/start_screen.dart';

// Глобальний клієнт Supabase для всього додатка
final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Ініціалізація Supabase
  await Supabase.initialize(
    url: 'https://wvaqqlitzzlaelkvmnyi.supabase.co',
    anonKey: 'sb_publishable_nCbSA8vx9QXVJWUPAvcBBQ_DO0NIBto',
  );

  // Push readiness (Phase 1): initialize Firebase core only. Guarded — on
  // failure the app continues with the existing Realtime-only alert delivery.
  // No permission prompt, token registration, or message handling happens yet.
  await PushService.initializeApp();

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
          .select('role')
          .eq('auth_id', user.id)
          .single();

      final role = UserRole.authorizationRole(userData);
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

      theme: KlychTheme.build(),

      home: FutureBuilder<Widget>(
        future: _initialScreenFuture,
        builder: (context, snapshot) {
          // Поки йде перевірка сесії та запит до Supabase — показуємо лоадер
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              backgroundColor: KlychTheme.background,
              body: Center(child: CircularProgressIndicator(color: KlychTheme.accent)),
            );
          }

          // Повертаємо визначений екран або дефолтний StartScreen, якщо щось пішло не так
          return snapshot.data ?? const StartScreen();
        },
      ),
    );
  }
}
