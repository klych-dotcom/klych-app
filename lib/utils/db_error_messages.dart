import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps PostgREST / Postgres errors to Ukrainian user-facing messages.
class DbErrorMessages {
  static String from(dynamic error, {String? fallback}) {
    if (error is PostgrestException) {
      if (error.code == '23505') {
        return 'Запис з такими даними вже існує.';
      }
      if (error.message.isNotEmpty) {
        return error.message;
      }
    }

    final text = error.toString();
    if (text.contains('23505') || text.contains('duplicate key')) {
      return 'Запис з такими даними вже існує.';
    }

    return fallback ?? 'Не вдалося зберегти дані. Спробуйте ще раз.';
  }
}
