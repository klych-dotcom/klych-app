/// Thrown when an alert has no valid recipients after targeting resolution.
class NoRecipientsException implements Exception {
  NoRecipientsException([
    this.message = 'Немає отримувачів для обраних фільтрів',
  ]);

  final String message;

  @override
  String toString() => message;
}
