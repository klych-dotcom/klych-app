import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/alert_exceptions.dart';
import '../models/alert_recipients_selection.dart';
import '../models/alert_constants.dart';
import '../services/alert_service.dart';
import '../services/alert_delivery_service.dart';
import '../services/alert_receipt_service.dart';
import '../services/recipient_resolver.dart';
import '../services/group_service.dart';
import '../services/user_org_service.dart';
import '../utils/alert_utils.dart';
import '../utils/alert_delivery_tracker.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import 'alert_screen.dart';
import 'leader_alert_details_screen.dart';
import 'leader_org_screen.dart';
import 'start_screen.dart';

class LeaderHomeScreen extends StatefulWidget {
  const LeaderHomeScreen({super.key, this.initialRecipients});

  final AlertRecipientsSelection? initialRecipients;

  @override
  State<LeaderHomeScreen> createState() => _LeaderHomeScreenState();
}

class _LeaderHomeScreenState extends State<LeaderHomeScreen> {
  final AssetsAudioPlayer player = AssetsAudioPlayer();
  final TextEditingController alertMessageController = TextEditingController();

  RealtimeChannel? channel;

  String callsign = 'LEADER';
  String organization = 'KLYCH';
  String? organizationId;
  String? currentUserId;

  bool connected = false;
  bool loading = true;
  bool sending = false;

  String selectedLevel = AlertLevel.red;
  late AlertRecipientsSelection alertRecipients;

  List<Map<String, dynamic>> alerts = [];
  List<Map<String, dynamic>> orgUsers = [];
  List<Map<String, dynamic>> orgGroups = [];

  final AlertDeliveryTracker _deliveryTracker = AlertDeliveryTracker();

  DateTime? _historyClearedAt;
  Timer? _historyReloadDebounce;

  @override
  void initState() {
    super.initState();
    alertRecipients = widget.initialRecipients ?? AlertRecipientsSelection();
    _init();
  }

  Future<void> _init() async {
    await loadUser();
    final prefs = await SharedPreferences.getInstance();
    final cleared = prefs.getString('leader_alerts_cleared_at');
    if (cleared != null) _historyClearedAt = DateTime.tryParse(cleared);
    await _loadOrgTargetingData();
    await _loadAlertHistory();
    subscribeAlerts();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadOrgTargetingData() async {
    if (organizationId == null) return;
    try {
      orgUsers = await UserOrgService.fetchOrgUsers(organizationId!);
      orgGroups = await GroupService.fetchGroups(organizationId!);
      _invalidateResolver();
    } catch (e) {
      debugPrint('LeaderHomeScreen._loadOrgTargetingData: $e');
    }
  }

  // Cached so recipient resolution is computed once per selection/data change
  // rather than several times on every rebuild (incl. connection-status ticks).
  RecipientResolver? _resolverCache;

  RecipientResolver get _resolvedRecipients => _resolverCache ??=
      alertRecipients.resolveRecipients(
        users: orgUsers,
        groups: orgGroups,
        excludeUserId: currentUserId,
      );

  void _invalidateResolver() => _resolverCache = null;

  int get _recipientCount => _resolvedRecipients.count;

  String get _recipientsDisplayLabel =>
      alertRecipients.recipientsLabel(count: _recipientCount);

  Future<void> loadUser() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', user.id)
          .single();

      organizationId = userData['organization_id']?.toString();
      currentUserId = userData['id']?.toString();

      final org = await supabase
          .from('organizations')
          .select('name')
          .eq('id', organizationId!)
          .single();

      if (!mounted) return;

      setState(() {
        callsign = userData['callsign'] ?? 'LEADER';
        organization = org['name'] ?? 'KLYCH';
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _loadAlertHistory() async {
    if (organizationId == null) return;
    try {
      final loaded = await AlertDeliveryService.fetchOrgAlertHistory(organizationId!);
      final filtered = loaded.where((alert) {
        if (_historyClearedAt == null) return true;
        final createdAt = DateTime.tryParse(alert['created_at']?.toString() ?? '');
        if (createdAt == null) return true;
        return createdAt.isAfter(_historyClearedAt!);
      }).toList();
      alerts = filtered;
      _deliveryTracker.seedFromHistory(alerts);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('$e');
    }
  }

  /// Coalesces bursts of realtime inserts into a single history refresh
  /// instead of firing a full network reload per event.
  void _scheduleHistoryReload() {
    _historyReloadDebounce?.cancel();
    _historyReloadDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _loadAlertHistory();
    });
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Очистити історію?'),
        content: const Text(
          'Історія оповіщень буде прихована на цьому пристрої. '
          'Дані в системі залишаться без змін.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('СКАСУВАТИ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('ОЧИСТИТИ', style: TextStyle(color: KlychTheme.alertRed)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      await prefs.setString('leader_alerts_cleared_at', now.toIso8601String());
      setState(() {
        _historyClearedAt = now;
        alerts.clear();
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  void subscribeAlerts() {
    if (organizationId == null) return;

    channel?.unsubscribe();

    final orgId = organizationId!;

    channel = supabase.channel('leader-alerts-$orgId');

    channel!
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
            await _handleIncomingAlert(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
          if (!mounted) return;
          setState(() {
            connected = status == RealtimeSubscribeStatus.subscribed;
          });
        });
  }

  Future<void> _handleIncomingAlert(Map<String, dynamic> data) async {
    if (organizationId == null || currentUserId == null) return;
    if (!_deliveryTracker.tryMarkProcessed(data)) return;

    _scheduleHistoryReload();

    final shouldReceive = await AlertDeliveryService.shouldUserReceiveAlert(
      alert: data,
      organizationId: organizationId!,
      userId: currentUserId!,
    );
    if (!shouldReceive) return;

    final authUserId = currentUserId;
    if (AlertDeliveryTracker.isOwnAlert(data, authUserId)) return;

    final alertId = data['id']?.toString();
    if (alertId != null && authUserId != null) {
      try {
        await AlertReceiptService.markDelivered(
          alertId: alertId,
          userId: authUserId,
        );
      } catch (e) {
        debugPrint('markDelivered: $e');
      }
    }

    if (AlertUtils.isRedAlert(AlertUtils.resolveLevel(data))) {
      await _triggerRedAlert(data);
    } else {
      _showGreenNotification(data);
    }
  }

  Future<void> _triggerRedAlert(Map<String, dynamic> alert) async {
    try {
      await player.open(
        Audio('assets/alarm.mp3'),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
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
            userId: currentUserId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  void _showGreenNotification(Map<String, dynamic> alert) {
    if (!mounted) return;

    final alertId = alert['id']?.toString();
    final userId = currentUserId;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade900,
        content: Text(alert['message']?.toString() ?? 'Інформаційне повідомлення'),
        action: alertId != null && userId != null
            ? SnackBarAction(
                label: 'ПІДТВЕРДИТИ',
                textColor: Colors.white,
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

  Future<void> sendAlert() async {
    if (organizationId == null || sending || currentUserId == null) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final resolved = _resolvedRecipients;
    if (!resolved.canSend) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(NoRecipientsException().message)),
        );
      }
      return;
    }

    final messageText = alertMessageController.text.trim();
    final message = messageText.isEmpty
        ? AlertService.defaultMessage(selectedLevel)
        : messageText;

    try {
      setState(() => sending = true);

      final inserted = await AlertService.createAlert(
        organizationId: organizationId!,
        message: message,
        level: selectedLevel,
        recipients: alertRecipients,
        senderUserId: currentUserId!,
      );

      if (_deliveryTracker.tryMarkProcessed(inserted)) {
        final optimistic = {
          ...inserted,
          'target_label': alertRecipients.recipientsLabel(count: resolved.count),
          'recipient_count': resolved.count,
          'acknowledged_count': 0,
        };
        setState(() {
          alerts.removeWhere((a) => a['id']?.toString() == inserted['id']?.toString());
          alerts.insert(0, optimistic);
        });
        _loadAlertHistory();
      }

      alertMessageController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Оповіщення надіслано')),
        );
      }
    } on NoRecipientsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Помилка: $e'),
            backgroundColor: KlychTheme.alertRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ВИЙТИ З СИСТЕМИ?'),
        content: const Text(
          'Для повторного доступу знадобиться новий код запрошення.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('СКАСУВАТИ', style: TextStyle(color: KlychTheme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ВИЙТИ',
              style: TextStyle(color: KlychTheme.alertRed, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const StartScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  String _alertHistorySubtitle(Map<String, dynamic> alert, String level) {
    final targetLabel =
        alert['target_label']?.toString() ?? _recipientsDisplayLabel;
    final ackTotal = alert['recipient_count'];
    final ackConfirmed = alert['acknowledged_count'];
    final ackSuffix = ackTotal is int && ackTotal > 0
        ? ' · ✓ $ackConfirmed/$ackTotal'
        : '';
    return '$level · $targetLabel$ackSuffix · '
        '${formatDate(alert['created_at'])} ${formatTime(alert['created_at'])}';
  }

  String formatTime(String? value) {
    if (value == null) return '--:--';
    try {
      return DateFormat('HH:mm').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '--:--';
    }
  }

  String formatDate(String? value) {
    if (value == null) return '--.--.----';
    try {
      return DateFormat('dd.MM.yyyy').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '--.--.----';
    }
  }

  @override
  void dispose() {
    _historyReloadDebounce?.cancel();
    channel?.unsubscribe();
    player.dispose();
    alertMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: KlychTheme.background,
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KlychTheme.spaceLg,
                        KlychTheme.spaceMd,
                        KlychTheme.spaceLg,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: KlychAppHeader(
                              organization: organization,
                              callsign: callsign,
                              connected: connected,
                            ),
                          ),
                          IconButton(
                            onPressed: () async {
                              final result = await Navigator.push<
                                  AlertRecipientsSelection>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LeaderOrgScreen(
                                    selectRecipientsMode: true,
                                  ),
                                ),
                              );
                              if (result != null && mounted) {
                                setState(() {
                                  alertRecipients = result;
                                  _invalidateResolver();
                                });
                              }
                            },
                            icon: const Icon(Icons.tune, color: KlychTheme.textSecondary),
                          ),
                          IconButton(
                            onPressed: logout,
                            icon: const Icon(Icons.logout, color: KlychTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KlychTheme.spaceMd),
                    // Primary action: large message composition area.
                    // Fixed height ~24mm on modern iPhones (≈6 logical px / mm).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KlychTheme.spaceLg,
                      ),
                      child: SizedBox(
                        height: 150,
                        child: TextField(
                          controller: alertMessageController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          style: KlychTheme.bodyLarge.copyWith(fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Текст оповіщення...',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: KlychTheme.spaceSm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KlychTheme.spaceLg),
                      child: Row(
                        children: [
                          Expanded(
                            child: AlertLevelSelector(
                              value: selectedLevel,
                              onChanged: (v) => setState(() => selectedLevel = v),
                            ),
                          ),
                          const SizedBox(width: KlychTheme.spaceSm),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton(
                              onPressed: () async {
                                final result =
                                    await Navigator.push<AlertRecipientsSelection>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LeaderOrgScreen(
                                      selectRecipientsMode: true,
                                    ),
                                  ),
                                );
                                if (result != null && mounted) {
                                  setState(() {
                                    alertRecipients = result;
                                    _invalidateResolver();
                                  });
                                }
                              },
                              child: Text(
                                _recipientsDisplayLabel,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KlychTheme.spaceSm),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KlychTheme.spaceLg),
                      child: KlychPrimaryButton(
                        label: sending ? 'НАДСИЛАННЯ...' : 'НАДІСЛАТИ',
                        loading: sending,
                        onPressed: sending || !_resolvedRecipients.canSend ? null : sendAlert,
                        color: selectedLevel == AlertLevel.red
                            ? KlychTheme.alertRed
                            : KlychTheme.alertGreen,
                      ),
                    ),
                    const SizedBox(height: KlychTheme.spaceMd),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: KlychTheme.spaceLg),
                      child: Row(
                        children: [
                          Text('ІСТОРІЯ ОПОВІЩЕНЬ', style: KlychTheme.labelCaps),
                          const Spacer(),
                          IconButton(
                            onPressed: alerts.isEmpty ? null : _confirmClearHistory,
                            icon: const Icon(Icons.delete_outline, size: 20),
                            color: KlychTheme.textMuted,
                            tooltip: 'Очистити історію',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: KlychTheme.spaceSm),
                    // Secondary: alert history fills the remaining space below the composer.
                    Expanded(
                      child: RefreshIndicator(
                          onRefresh: _loadAlertHistory,
                          color: KlychTheme.accent,
                          child: alerts.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 80),
                                    KlychEmptyState(message: 'Немає активності'),
                                  ],
                                )
                              : ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: KlychTheme.spaceLg,
                                  ),
                                  itemCount: alerts.length,
                                  itemBuilder: (_, index) {
                                    final alert = alerts[index];
                                    final level = AlertUtils.levelLabelFromAlert(alert);
                                    final isGreen = level == AlertLevel.green;

                                    return KlychAlertHistoryTile(
                                      message: alert['message']?.toString() ?? 'ALERT',
                                      subtitle: _alertHistorySubtitle(alert, level),
                                      isGreen: isGreen,
                                      onTap: alert['id'] != null
                                          ? () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      LeaderAlertDetailsScreen(
                                                    alert: alert,
                                                  ),
                                                ),
                                              );
                                            }
                                          : null,
                                    );
                                  },
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
