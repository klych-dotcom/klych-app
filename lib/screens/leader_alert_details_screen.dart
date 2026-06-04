import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/alert_constants.dart';
import '../services/alert_receipt_service.dart';
import '../theme/klych_theme.dart';
import '../utils/alert_utils.dart';
import '../widgets/klych_components.dart';

class LeaderAlertDetailsScreen extends StatefulWidget {
  const LeaderAlertDetailsScreen({super.key, required this.alert});

  final Map<String, dynamic> alert;

  @override
  State<LeaderAlertDetailsScreen> createState() =>
      _LeaderAlertDetailsScreenState();
}

class _LeaderAlertDetailsScreenState extends State<LeaderAlertDetailsScreen> {
  bool loading = true;
  List<Map<String, dynamic>> receipts = [];
  RealtimeChannel? _channel;
  Timer? _reloadDebounce;

  String? get _alertId => widget.alert['id']?.toString();

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  Future<void> _load() async {
    final alertId = _alertId;
    if (alertId == null) {
      if (mounted) setState(() => loading = false);
      return;
    }

    try {
      receipts = await AlertReceiptService.fetchForAlert(alertId);
    } catch (e) {
      debugPrint('LeaderAlertDetailsScreen._load: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  void _subscribe() {
    final alertId = _alertId;
    if (alertId == null) return;

    _channel?.unsubscribe();
    _channel = AlertReceiptService.subscribeToAlertReceipts(
      alertId: alertId,
      onChange: (_) => _scheduleReload(),
    );
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  String _formatTs(String? value) {
    if (value == null) return '—';
    try {
      return DateFormat('dd.MM.yyyy HH:mm')
          .format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '—';
    }
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final level = AlertUtils.levelLabelFromAlert(widget.alert);
    final isGreen = level == AlertLevel.green;
    final confirmed = receipts
        .where(
          (r) =>
              AlertReceiptService.displayStatus(r) ==
              ReceiptDisplayStatus.confirmed,
        )
        .length;
    final createdAt = _formatTs(widget.alert['created_at']?.toString());

    return Scaffold(
      appBar: AppBar(title: const Text('ДЕТАЛІ ОПОВІЩЕННЯ')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(KlychTheme.spaceLg),
                  child: KlychCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.alert['message']?.toString() ?? '—',
                          style: KlychTheme.titleMedium,
                        ),
                        const SizedBox(height: KlychTheme.spaceSm),
                        Text(
                          '$level · ${widget.alert['target_label'] ?? '—'}',
                          style: KlychTheme.bodyMedium.copyWith(
                            fontSize: 12,
                            color: isGreen ? KlychTheme.alertGreen : KlychTheme.alertRed,
                          ),
                        ),
                        const SizedBox(height: KlychTheme.spaceSm),
                        Text(
                          'Створено: $createdAt',
                          style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                        ),
                        const SizedBox(height: KlychTheme.spaceXs),
                        Text(
                          'ОТРИМУВАЧІ: ${receipts.length} · ✓ $confirmed',
                          style: KlychTheme.bodyMedium.copyWith(
                            color: KlychTheme.statusDeployed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: KlychTheme.spaceLg),
                  child: KlychSectionHeader(title: 'ОТРИМУВАЧІ'),
                ),
                Expanded(
                  child: receipts.isEmpty
                      ? const KlychEmptyState(message: 'Немає даних про отримувачів')
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: KlychTheme.spaceLg,
                          ),
                          itemCount: receipts.length,
                          itemBuilder: (_, i) {
                            final receipt = receipts[i];
                            final status =
                                AlertReceiptService.displayStatus(receipt);
                            final label =
                                AlertReceiptService.statusLabel(status);

                            return KlychCard(
                              padding: const EdgeInsets.all(KlychTheme.spaceMd),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          AlertReceiptService.callsign(receipt)
                                              .toUpperCase(),
                                          style: KlychTheme.titleMedium.copyWith(
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        label,
                                        style: KlychTheme.bodyMedium.copyWith(
                                          fontSize: 12,
                                          color: status ==
                                                  ReceiptDisplayStatus.confirmed
                                              ? KlychTheme.alertGreen
                                              : KlychTheme.statusDeployed,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: KlychTheme.spaceSm),
                                  Text(
                                    'Створено: ${_formatTs(widget.alert['created_at']?.toString())}',
                                    style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                                  ),
                                  Text(
                                    'Підтверджено: ${_formatTs(receipt['acknowledged_at']?.toString())}',
                                    style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
