import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/user_role.dart';
import '../models/user_status.dart';
import '../services/user_org_service.dart';
import '../theme/klych_theme.dart';
import '../utils/department_labels.dart';
import 'klych_components.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  Color get _color => KlychTheme.statusColor(UserStatus.normalize(status));

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KlychTheme.spaceSm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KlychTheme.radiusSm),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Text(
        UserStatus.label(status),
        style: TextStyle(
          color: _color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class UserOrgListTile extends StatelessWidget {
  const UserOrgListTile({
    super.key,
    required this.user,
    this.onTap,
    this.trailing,
    this.leading,
    this.selected = false,
    this.compact = false,
  });

  final Map<String, dynamic> user;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? leading;
  final bool selected;
  final bool compact;

  String _formatDate(String? value) {
    if (value == null) return '—';
    try {
      return DateFormat('dd.MM.yyyy HH:mm')
          .format(DateTime.parse(value).toLocal());
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = UserRole.authorizationRole(user);
    final disabled = user['is_disabled'] == true;
    final status = user['status']?.toString() ?? UserStatus.available;
    final roleColor = KlychTheme.roleColor(role);

    if (compact) {
      // High-density single-line row: callsign · department · status.
      return Opacity(
        opacity: disabled ? 0.5 : 1,
        child: KlychCard(
          selected: selected,
          onTap: onTap,
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(
            horizontal: KlychTheme.spaceMd,
            vertical: 7,
          ),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: KlychTheme.spaceSm)],
              Text(
                (user['callsign'] ?? 'UNKNOWN').toString(),
                style: KlychTheme.titleMedium.copyWith(fontSize: 14),
              ),
              const SizedBox(width: KlychTheme.spaceSm),
              Expanded(
                child: Text(
                  UserOrgService.departmentName(user),
                  style: KlychTheme.bodyMedium.copyWith(
                    fontSize: 11,
                    color: KlychTheme.textMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: KlychTheme.spaceSm),
              StatusBadge(status: status),
              ?trailing,
            ],
          ),
        ),
      );
    }

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: KlychCard(
        selected: selected,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: KlychTheme.spaceMd)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (user['callsign'] ?? 'UNKNOWN').toString(),
                    style: KlychTheme.titleMedium,
                  ),
                  const SizedBox(height: KlychTheme.spaceXs),
                  Text(
                    '${role.toUpperCase()} · ${UserOrgService.departmentName(user)}',
                    style: KlychTheme.bodyMedium.copyWith(color: roleColor),
                  ),
                  const SizedBox(height: KlychTheme.spaceSm),
                  StatusBadge(status: status),
                  const SizedBox(height: KlychTheme.spaceSm),
                  Text(
                    'Реєстрація: ${_formatDate(user['created_at']?.toString())}',
                    style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                  ),
                  Text(
                    'Активність: ${_formatDate(user['last_activity_at']?.toString())}',
                    style: KlychTheme.bodyMedium.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class OrgStatusSummary extends StatelessWidget {
  const OrgStatusSummary({
    super.key,
    required this.counts,
    this.selectedStatuses = const {},
    this.onStatusToggle,
  });

  final Map<String, int> counts;
  final Set<String> selectedStatuses;
  final ValueChanged<String>? onStatusToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: KlychTheme.spaceSm,
      runSpacing: KlychTheme.spaceSm,
      children: UserStatus.all.map((status) {
        return KlychFilterChip(
          label: '${UserStatus.label(status)}: ${counts[status] ?? 0}',
          selected: selectedStatuses.contains(status),
          onSelected: onStatusToggle == null
              ? (_) {}
              : (_) => onStatusToggle!(status),
          selectedColor: KlychTheme.statusColor(status),
        );
      }).toList(),
    );
  }
}

class DepartmentFilterChips extends StatelessWidget {
  const DepartmentFilterChips({
    super.key,
    required this.departments,
    this.selectedDepartmentIds = const {},
    this.onDepartmentToggle,
  });

  final List<Map<String, dynamic>> departments;
  final Set<String> selectedDepartmentIds;
  final void Function(String id, String name)? onDepartmentToggle;

  @override
  Widget build(BuildContext context) {
    if (departments.isEmpty) {
      return Text('—', style: KlychTheme.bodyMedium);
    }

    return Wrap(
      spacing: KlychTheme.spaceSm,
      runSpacing: KlychTheme.spaceSm,
      children: departments.map((dept) {
        final id = dept['id']?.toString();
        if (id == null) return const SizedBox.shrink();
        final name = DepartmentLabels.localize(dept['name']?.toString());
        return KlychFilterChip(
          label: name,
          selected: selectedDepartmentIds.contains(id),
          onSelected: onDepartmentToggle == null
              ? (_) {}
              : (_) => onDepartmentToggle!(id, dept['name']?.toString() ?? name),
          selectedColor: KlychTheme.statusOnDuty,
        );
      }).toList(),
    );
  }
}
