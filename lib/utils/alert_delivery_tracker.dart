/// Tracks processed alert events to prevent duplicate UI and history entries.
class AlertDeliveryTracker {
  final Set<String> _processedIds = {};

  /// Stable id for deduplication — prefers DB [id], falls back to composite key.
  static String? alertKey(Map<String, dynamic> alert) {
    final id = alert['id'];
    if (id != null && id.toString().isNotEmpty) {
      return id.toString();
    }

    final senderId = alert['sender_user_id']?.toString();
    final createdAt = alert['created_at']?.toString();
    final message = alert['message']?.toString();

    if (senderId != null && createdAt != null && message != null) {
      return '$senderId|$createdAt|$message';
    }

    return null;
  }

  /// Returns true the first time this alert is seen; false for duplicates.
  bool tryMarkProcessed(Map<String, dynamic> alert) {
    final key = alertKey(alert);
    if (key == null) return true;
    return _processedIds.add(key);
  }

  /// Whether the current user ([users.id]) sent this alert.
  static bool isOwnAlert(Map<String, dynamic> alert, String? currentUserId) {
    if (currentUserId == null || currentUserId.isEmpty) return false;
    return alert['sender_user_id']?.toString() == currentUserId;
  }

  /// Pre-register ids loaded from local history so restarts do not re-notify.
  void seedFromHistory(Iterable<Map<String, dynamic>> history) {
    for (final alert in history) {
      final key = alertKey(alert);
      if (key != null) _processedIds.add(key);
    }
  }
}
