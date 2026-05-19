import 'package:flutter/material.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';

class AlertScreen extends StatelessWidget {
  final Map<String, dynamic> alert;
  final AssetsAudioPlayer player;

  const AlertScreen({super.key, required this.alert, required this.player});

  Future<void> stopAlert(BuildContext context) async {
    await player.stop();

    Vibration.cancel();

    if (!context.mounted) return;

    Navigator.pop(context);
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
                alert['message'] ?? 'ALERT',

                textAlign: TextAlign.center,

                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 18),

              Text(
                'TYPE: ${alert['type'] ?? 'GENERAL'}',

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
                  onPressed: () => stopAlert(context),

                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),

                  child: const Text(
                    'ЗУПИНИТИ ТРИВОГУ',

                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
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
