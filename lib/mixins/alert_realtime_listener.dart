import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibration/vibration.dart';

import '../main.dart';
import '../services/alert_delivery_service.dart';
import '../services/alert_receipt_service.dart';
import '../theme/klych_theme.dart';
import '../utils/alert_delivery_tracker.dart';
import '../utils/alert_utils.dart';
import '../screens/alert_screen.dart';

/// Shared realtime alert delivery for admin, leader, and member screens.
mixin AlertRealtimeListener<T extends StatefulWidget> on State<T> {
  RealtimeChannel? alertChannel;
  final AlertDeliveryTracker deliveryTracker = AlertDeliveryTracker();
  AssetsAudioPlayer? alertPlayer;

  String? get alertOrganizationId;
  String? get alertCurrentUserId;
  AssetsAudioPlayer getOrCreatePlayer() =>
      alertPlayer ??= AssetsAudioPlayer();

  void subscribeOrgAlerts(String channelPrefix) {
    final orgId = alertOrganizationId;
    if (orgId == null) return;

    alertChannel?.unsubscribe();
    alertChannel = supabase.channel('$channelPrefix-$orgId');

    alertChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'alerts',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organization_id',
            value: orgId,
          ),
          callback: (payload) async {
            await handleIncomingAlert(payload.newRecord);
          },
        )
        .subscribe();
  }

  void disposeAlertRealtime() {
    alertChannel?.unsubscribe();
    alertPlayer?.dispose();
  }

  /// Override to refresh history UI when any org alert arrives.
  Future<void> onOrgAlertInserted(Map<String, dynamic> alert);

  Future<void> handleIncomingAlert(Map<String, dynamic> data) async {
    final orgId = alertOrganizationId;
    final userId = alertCurrentUserId;
    if (orgId == null || userId == null) return;
    if (!deliveryTracker.tryMarkProcessed(data)) return;

    await onOrgAlertInserted(data);

    final shouldReceive = await AlertDeliveryService.shouldUserReceiveAlert(
      alert: data,
      organizationId: orgId,
      userId: userId,
    );
    if (!shouldReceive) return;
    if (AlertDeliveryTracker.isOwnAlert(data, userId)) return;

    final alertId = data['id']?.toString();
    if (alertId != null) {
      try {
        await AlertReceiptService.markDelivered(
          alertId: alertId,
          userId: userId,
        );
      } catch (e) {
        debugPrint('markDelivered: $e');
      }
    }

    if (AlertUtils.isRedAlert(AlertUtils.resolveLevel(data))) {
      await triggerRedAlert(data);
    } else {
      showGreenAlertSnackBar(data);
    }
  }

  Future<void> triggerRedAlert(Map<String, dynamic> alert) async {
    try {
      final player = getOrCreatePlayer();
      await player.open(
        Audio('assets/alarm.mp3'),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      if (await Vibration.hasVibrator()) {
        Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 0);
      }

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AlertScreen(
            alert: alert,
            player: player,
            userId: alertCurrentUserId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('triggerRedAlert: $e');
    }
  }

  void showGreenAlertSnackBar(Map<String, dynamic> alert) {
    if (!mounted) return;

    final alertId = alert['id']?.toString();
    final userId = alertCurrentUserId;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: KlychTheme.alertGreenSoft,
        content: Text(
          alert['message']?.toString() ?? 'Інформаційне повідомлення',
          style: const TextStyle(color: KlychTheme.textPrimary),
        ),
        action: alertId != null && userId != null
            ? SnackBarAction(
                label: 'ПІДТВЕРДИТИ',
                textColor: KlychTheme.alertGreen,
                onPressed: () async {
                  try {
                    await AlertReceiptService.markOpened(
                      alertId: alertId,
                      userId: userId,
                    );
                    await AlertReceiptService.markAcknowledged(
                      alertId: alertId,
                      userId: userId,
                    );
                  } catch (e) {
                    debugPrint('green ack: $e');
                  }
                },
              )
            : null,
      ),
    );
  }
}
