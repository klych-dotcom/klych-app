/// User operational status — changed by the user; visible to leaders in realtime.
class UserStatus {
  static const available = 'available';
  static const onDuty = 'on_duty';
  static const deployed = 'deployed';
  static const vacation = 'vacation';
  static const unavailable = 'unavailable';

  static const all = [available, onDuty, deployed, vacation, unavailable];

  static const labels = {
    available: 'Резерв',
    onDuty: 'Чергова зміна',
    deployed: 'На виїзді',
    vacation: 'Відсутній',
    unavailable: 'Недоступний',
  };

  static String label(String? status) {
    return labels[normalize(status)] ?? labels[available]!;
  }

  static String normalize(String? status) {
    final value = status?.trim().toLowerCase();
    if (value != null && all.contains(value)) return value;
    return available;
  }
}
