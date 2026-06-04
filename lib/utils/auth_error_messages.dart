import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps Supabase Auth errors to Ukrainian user-facing messages.
class AuthErrorMessages {
  static String from(dynamic error) {
    if (error is AuthException) {
      final byCode = _fromCode(error.code);
      if (byCode != null) return byCode;
      return _fromText(error.message) ?? error.message;
    }

    return _fromText(error.toString()) ?? 'Сталася помилка. Спробуйте ще раз.';
  }

  static String? _fromCode(String? code) {
    if (code == null || code.isEmpty) return null;

    switch (code.toLowerCase()) {
      case 'over_email_send_rate_limit':
        return 'Забагато листів підтвердження. Спробуйте пізніше.';
      case 'invalid_credentials':
        return 'Невірний email або пароль.';
      case 'email_not_confirmed':
        return 'Підтвердіть email перед входом.';
      case 'user_already_registered':
        return 'Користувач з таким email вже зареєстрований.';
      case 'weak_password':
        return 'Пароль занадто слабкий. Мінімум 6 символів.';
      case 'signup_disabled':
        return 'Реєстрація тимчасово вимкнена.';
      case 'email_address_invalid':
        return 'Невірний формат email.';
      case 'user_not_found':
        return 'Користувача не знайдено.';
      case 'too_many_requests':
        return 'Забагато спроб. Зачекайте і спробуйте знову.';
      default:
        return null;
    }
  }

  static String? _fromText(String text) {
    final normalized = text.toLowerCase();

    if (normalized.contains('over_email_send_rate_limit') ||
        normalized.contains('email rate limit')) {
      return 'Забагато листів підтвердження. Спробуйте пізніше.';
    }
    if (normalized.contains('invalid_credentials') ||
        normalized.contains('invalid login credentials')) {
      return 'Невірний email або пароль.';
    }
    if (normalized.contains('email_not_confirmed') ||
        normalized.contains('email not confirmed')) {
      return 'Підтвердіть email перед входом.';
    }
    if (normalized.contains('user already registered')) {
      return 'Користувач з таким email вже зареєстрований.';
    }
    if (normalized.contains('weak password') ||
        normalized.contains('password should be at least')) {
      return 'Пароль занадто слабкий. Мінімум 6 символів.';
    }
    if (normalized.contains('network') || normalized.contains('socket')) {
      return 'Проблема з мережею. Перевірте підключення.';
    }

    return null;
  }
}
