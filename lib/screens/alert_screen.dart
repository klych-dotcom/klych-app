import 'package:flutter/material.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';

import '../services/alert_receipt_service.dart';
import '../utils/alert_utils.dart';

class AlertScreen extends StatefulWidget {
  const AlertScreen({
    super.key,
    required this.alert,
    required this.player,
    this.userId,
  });

  final Map<String, dynamic> alert;
  final AssetsAudioPlayer player;
  final String? userId;

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  bool acknowledging = false;

  String? get _alertId => widget.alert['id']?.toString();

  @override
  void initState() {
    super.initState();
    _markOpened();
  }

  Future<void> _markOpened() async {
    final alertId = _alertId;
    final userId = widget.userId;
    if (alertId == null || userId == null) return;

    try {
      await AlertReceiptService.markOpened(alertId: alertId, userId: userId);
    } catch (e) {
      debugPrint('AlertScreen._markOpened: $e');
    }
  }

  Future<void> _confirmReceipt(BuildContext context) async {
    if (acknowledging) return;

    setState(() => acknowledging = true);

    try {
      final alertId = _alertId;
      final userId = widget.userId;
      if (alertId != null && userId != null) {
        await AlertReceiptService.markAcknowledged(
          alertId: alertId,
          userId: userId,
        );
      }

      await widget.player.stop();
      Vibration.cancel();

      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('AlertScreen._confirmReceipt: $e');
      if (mounted) setState(() => acknowledging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 120),
              const SizedBox(height: 40),
              const Text(
                'ТРИВОГА',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.alert['message'] ?? 'ALERT',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'LEVEL: ${AlertUtils.levelLabel(AlertUtils.resolveLevel(widget.alert))}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 70,
                child: ElevatedButton(
                  onPressed: acknowledging ? null : () => _confirmReceipt(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Text(
                    acknowledging ? 'ЗБЕРЕЖЕННЯ...' : 'ПІДТВЕРДИТИ ОТРИМАННЯ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
