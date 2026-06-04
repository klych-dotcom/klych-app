import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:assets_audio_player/assets_audio_player.dart';
import 'package:vibration/vibration.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/user_role.dart';
import '../models/alert_constants.dart';
import '../models/user_status.dart';
import '../services/user_org_service.dart';
import '../services/alert_delivery_service.dart';
import '../services/alert_receipt_service.dart';
import '../theme/klych_theme.dart';
import '../widgets/klych_components.dart';
import '../widgets/member_status_selector.dart';
import '../utils/alert_utils.dart';
import '../utils/alert_delivery_tracker.dart';
import 'alert_screen.dart';
import 'join_server_screen.dart';
import 'profile_screen.dart';

class MemberHomeScreen extends StatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  State<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends State<MemberHomeScreen> {
  final AssetsAudioPlayer player = AssetsAudioPlayer();

  RealtimeChannel? channel;

  String callsign = 'MEMBER';
  String role = UserRole.member;
  String organization = 'KLYCH';
  String? organizationId;
  String? currentUserId;
  String selectedStatus = UserStatus.available;
  bool updatingStatus = false;

  bool connected = false;

  List<Map<String, dynamic>> alerts = [];

  final AlertDeliveryTracker _deliveryTracker = AlertDeliveryTracker();

  DateTime? clearedAt;
  Timer? _historyReloadDebounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await loadUser();
    final prefs = await SharedPreferences.getInstance();
    final cleared = prefs.getString('alerts_cleared_at');
    if (cleared != null) clearedAt = DateTime.tryParse(cleared);
    await _loadAlertHistory();
    subscribeAlerts();
  }

  Future<void> loadUser() async {
    try {
      final user = supabase.auth.currentUser;

      if (user == null) return;

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', user.id)
          .single();

      final org = await supabase
          .from('organizations')
          .select()
          .eq('id', userData['organization_id'])
          .single();

      if (!mounted) return;

      setState(() {
        organizationId = userData['organization_id']?.toString();
        currentUserId = userData['id']?.toString();
        callsign = userData['callsign'] ?? 'MEMBER';
        selectedStatus = UserStatus.normalize(userData['status']?.toString());
        role = UserRole.authorizationRole(userData);
        organization = org['name'] ?? 'KLYCH';
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  Future<void> _loadAlertHistory() async {
    final orgId = organizationId;
    final userId = currentUserId;
    if (orgId == null || userId == null) return;

    try {
      final loaded = await AlertDeliveryService.fetchUserAlertHistory(
        userId: userId,
        organizationId: orgId,
      );

      final filtered = loaded.where((alert) {
        if (clearedAt == null) return true;
        final createdAt = DateTime.tryParse(alert['created_at']?.toString() ?? '');
        if (createdAt == null) return true;
        return createdAt.isAfter(clearedAt!);
      }).toList();

      if (!mounted) return;
      setState(() => alerts = filtered);
      _deliveryTracker.seedFromHistory(alerts);
    } catch (e) {
      debugPrint('_loadAlertHistory: $e');
    }
  }

  /// Coalesces rapid realtime inserts into a single history refresh.
  void _scheduleHistoryReload() {
    _historyReloadDebounce?.cancel();
    _historyReloadDebounce = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _loadAlertHistory();
    });
  }

  Future<void> clearAlerts() async {
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
      await prefs.setString('alerts_cleared_at', now.toIso8601String());

      setState(() {
        alerts.clear();
        clearedAt = now;
      });
    } catch (e) {
      debugPrint('$e');
    }
  }

  void subscribeAlerts() {
    if (organizationId == null) return;

    channel?.unsubscribe();

    final orgId = organizationId!;

    channel = supabase.channel('member-alerts-$orgId');

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
            await _handleIncomingAlert(payload.newRecord, orgId);
          },
        )
        .subscribe((status, [error]) {
          if (!mounted) return;
          setState(() {
            connected = status == RealtimeSubscribeStatus.subscribed;
          });
        });
  }

  Future<void> _handleIncomingAlert(
    Map<String, dynamic> data,
    String orgId,
  ) async {
    if (!_deliveryTracker.tryMarkProcessed(data)) return;

    final userId = currentUserId;
    if (userId == null) return;

    final shouldReceive = await AlertDeliveryService.shouldUserReceiveAlert(
      alert: data,
      organizationId: orgId,
      userId: userId,
    );
    if (!shouldReceive) return;

    _scheduleHistoryReload();

    if (!mounted) return;

    final currentId = currentUserId;
    if (AlertDeliveryTracker.isOwnAlert(data, currentId)) return;

    final alertId = data['id']?.toString();
    if (alertId != null && currentId != null) {
      try {
        await AlertReceiptService.markDelivered(
          alertId: alertId,
          userId: currentId,
        );
      } catch (e) {
        debugPrint('markDelivered: $e');
      }
    }

    if (AlertUtils.isRedAlert(AlertUtils.resolveLevel(data))) {
      await triggerRedAlert(data);
    } else {
      showGreenNotification(data);
    }
  }

  void showGreenNotification(Map<String, dynamic> alert) {
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

  Future<void> triggerRedAlert(Map<String, dynamic> alert) async {
    try {
      await player.open(
        Audio("assets/alarm.mp3"),
        autoStart: true,
        loopMode: LoopMode.single,
      );

      final hasVibrator = await Vibration.hasVibrator();

      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 1000, 500, 1000], repeat: 0);
      }

      if (!mounted) return;

      Navigator.push(
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

  Future<void> _updateStatus(String status) async {
    if (currentUserId == null || updatingStatus) return;

    setState(() {
      updatingStatus = true;
      selectedStatus = status;
    });

    try {
      await UserOrgService.updateStatus(
        userId: currentUserId!,
        status: status,
      );
    } catch (e) {
      debugPrint('$e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Не вдалося оновити статус'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => updatingStatus = false);
    }
  }

  Future<void> logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('ВИЙТИ З СИСТЕМИ?'),
          content: const Text(
            'Локальна історія оповіщень буде очищена з пристрою.\n\nДля повторного доступу знадобиться повторна авторизація.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text(
                'СКАСУВАТИ',
                style: TextStyle(color: KlychTheme.textMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text(
                'ВИЙТИ',
                style: TextStyle(
                  color: KlychTheme.alertRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove('alerts_history');

      await prefs.remove('alerts_cleared_at');

      await supabase.auth.signOut();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const JoinServerScreen()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('$e');
    }
  }

  String formatDate(String? value) {
    if (value == null) return '--.--.----';

    try {
      final date = DateTime.parse(value).toLocal();

      return DateFormat('dd.MM.yyyy').format(date);
    } catch (e) {
      return '--.--.----';
    }
  }

  String formatTime(String? value) {
    if (value == null) return '--:--';

    try {
      final date = DateTime.parse(value).toLocal();

      return DateFormat('HH:mm').format(date);
    } catch (e) {
      return '--:--';
    }
  }

  @override
  void dispose() {
    _historyReloadDebounce?.cancel();
    channel?.unsubscribe();

    player.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KlychTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(KlychTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: KlychAppHeader(
                      organization: organization,
                      callsign: callsign,
                      connected: connected,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      );
                    },
                    icon: const Icon(Icons.person_outline, color: KlychTheme.textSecondary),
                  ),
                  IconButton(
                    onPressed: logout,
                    icon: const Icon(Icons.logout, color: KlychTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: KlychTheme.spaceLg),
              KlychCard(
                padding: const EdgeInsets.all(KlychTheme.spaceLg),
                child: MemberStatusSelector(
                  selectedStatus: selectedStatus,
                  enabled: !updatingStatus,
                  onChanged: _updateStatus,
                ),
              ),
              const SizedBox(height: KlychTheme.spaceMd),
              Row(
                children: [
                  Text('ІСТОРІЯ ОПОВІЩЕНЬ', style: KlychTheme.labelCaps),
                  const Spacer(),
                  IconButton(
                    onPressed: alerts.isEmpty ? null : clearAlerts,
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: KlychTheme.textMuted,
                    tooltip: 'Очистити історію',
                  ),
                ],
              ),
              const SizedBox(height: KlychTheme.spaceSm),
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.42,
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
                          itemCount: alerts.length,
                          itemBuilder: (_, index) {
                            final alert = alerts[index];
                            final level = AlertUtils.levelLabelFromAlert(alert);
                            final isGreen = level == AlertLevel.green;

                            return KlychAlertHistoryTile(
                              message: alert['message']?.toString() ?? 'ALERT',
                              subtitle:
                                  '$level · ${formatDate(alert['created_at'])} · ${formatTime(alert['created_at'])}',
                              isGreen: isGreen,
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
