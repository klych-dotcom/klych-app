import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// Per-user alert delivery and acknowledgement tracking (`alert_receipts`).
class AlertReceiptService {
  static const _receiptSelect =
      'id, alert_id, user_id, delivered_at, opened_at, acknowledged_at, created_at, '
      'users!alert_receipts_user_id_fkey(id, callsign)';

  static String _nowUtc() => DateTime.now().toUtc().toIso8601String();

  /// One row per intended recipient when an alert is created.
  static Future<void> createReceiptsForAlert({
    required String alertId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) return;

    final rows = userIds
        .map(
          (userId) => {
            'alert_id': alertId,
            'user_id': userId,
          },
        )
        .toList();

    try {
      await supabase.from('alert_receipts').insert(rows);
      debugPrint(
        'AlertReceiptService.createReceiptsForAlert alert=$alertId count=${rows.length}',
      );
    } on PostgrestException catch (e) {
      debugPrint('AlertReceiptService.createReceiptsForAlert: $e');
      rethrow;
    }
  }

  static Future<bool> hasReceipt({
    required String alertId,
    required String userId,
  }) async {
    final row = await supabase
        .from('alert_receipts')
        .select('id')
        .eq('alert_id', alertId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  static Future<AlertAckStats> fetchAckStatsForAlert(String alertId) async {
    final rows = await supabase
        .from('alert_receipts')
        .select('acknowledged_at')
        .eq('alert_id', alertId);

    final list = List<Map<String, dynamic>>.from(rows);
    final confirmed = list.where((r) => r['acknowledged_at'] != null).length;
    return AlertAckStats(total: list.length, confirmed: confirmed);
  }

  static Future<Map<String, AlertAckStats>> fetchAckStatsForAlerts(
    List<String> alertIds,
  ) async {
    if (alertIds.isEmpty) return {};

    final rows = await supabase
        .from('alert_receipts')
        .select('alert_id, acknowledged_at')
        .inFilter('alert_id', alertIds);

    final stats = <String, AlertAckStats>{};
    for (final id in alertIds) {
      stats[id] = AlertAckStats(total: 0, confirmed: 0);
    }

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final alertId = row['alert_id']?.toString();
      if (alertId == null) continue;
      final current = stats[alertId] ?? AlertAckStats(total: 0, confirmed: 0);
      stats[alertId] = AlertAckStats(
        total: current.total + 1,
        confirmed: current.confirmed +
            (row['acknowledged_at'] != null ? 1 : 0),
      );
    }

    return stats;
  }

  static Future<void> markDelivered({
    required String alertId,
    required String userId,
  }) async {
    await _setTimestamp(
      alertId: alertId,
      userId: userId,
      field: 'delivered_at',
    );
  }

  static Future<void> markOpened({
    required String alertId,
    required String userId,
  }) async {
    await _setTimestamp(
      alertId: alertId,
      userId: userId,
      field: 'opened_at',
    );
  }

  static Future<void> markAcknowledged({
    required String alertId,
    required String userId,
  }) async {
    if (!await hasReceipt(alertId: alertId, userId: userId)) {
      debugPrint(
        'AlertReceiptService.markAcknowledged: no receipt for $userId',
      );
      return;
    }

    final now = _nowUtc();
    final existing = await _fetchRow(alertId: alertId, userId: userId);
    final patch = <String, dynamic>{'acknowledged_at': now};

    if (existing?['opened_at'] == null) patch['opened_at'] = now;
    if (existing?['delivered_at'] == null) patch['delivered_at'] = now;

    await supabase
        .from('alert_receipts')
        .update(patch)
        .eq('alert_id', alertId)
        .eq('user_id', userId);

    debugPrint('AlertReceiptService.markAcknowledged alert=$alertId user=$userId');
  }

  static Future<List<Map<String, dynamic>>> fetchForAlert(String alertId) async {
    final rows = await supabase
        .from('alert_receipts')
        .select(_receiptSelect)
        .eq('alert_id', alertId)
        .order('created_at');

    return List<Map<String, dynamic>>.from(rows);
  }

  static RealtimeChannel subscribeToAlertReceipts({
    required String alertId,
    required void Function(PostgresChangePayload payload) onChange,
  }) {
    final channel = supabase.channel('alert-receipts-$alertId');

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'alert_receipts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'alert_id',
            value: alertId,
          ),
          callback: onChange,
        )
        .subscribe();

    return channel;
  }

  static String callsign(Map<String, dynamic> receipt) {
    final users = receipt['users'];
    if (users is Map) {
      return users['callsign']?.toString() ?? '—';
    }
    return receipt['user_id']?.toString().substring(0, 8) ?? '—';
  }

  /// ✓ Confirmed · ⏳ Waiting · ❌ Not opened
  static ReceiptDisplayStatus displayStatus(Map<String, dynamic> receipt) {
    if (receipt['acknowledged_at'] != null) {
      return ReceiptDisplayStatus.confirmed;
    }
    if (receipt['opened_at'] != null) {
      return ReceiptDisplayStatus.waiting;
    }
    return ReceiptDisplayStatus.notOpened;
  }

  static String statusLabel(ReceiptDisplayStatus status) {
    switch (status) {
      case ReceiptDisplayStatus.confirmed:
        return '✓ Підтверджено';
      case ReceiptDisplayStatus.waiting:
        return '⏳ Очікує';
      case ReceiptDisplayStatus.notOpened:
        return '❌ Не відкрито';
    }
  }

  static Future<void> _setTimestamp({
    required String alertId,
    required String userId,
    required String field,
  }) async {
    if (!await hasReceipt(alertId: alertId, userId: userId)) return;

    final existing = await _fetchRow(alertId: alertId, userId: userId);
    if (existing?[field] != null) return;

    await supabase
        .from('alert_receipts')
        .update({field: _nowUtc()})
        .eq('alert_id', alertId)
        .eq('user_id', userId);
  }

  static Future<Map<String, dynamic>?> _fetchRow({
    required String alertId,
    required String userId,
  }) async {
    final row = await supabase
        .from('alert_receipts')
        .select('delivered_at, opened_at, acknowledged_at')
        .eq('alert_id', alertId)
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }
}

enum ReceiptDisplayStatus {
  confirmed,
  waiting,
  notOpened,
}

class AlertAckStats {
  const AlertAckStats({required this.total, required this.confirmed});

  final int total;
  final int confirmed;
}
