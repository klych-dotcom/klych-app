import 'package:flutter/material.dart';

import '../models/alert_constants.dart';
import '../theme/klych_theme.dart';
import 'linkified_text.dart';

class KlychCard extends StatelessWidget {
  const KlychCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.selected = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool selected;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: padding ?? const EdgeInsets.all(KlychTheme.spaceLg),
      child: child,
    );

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: KlychTheme.spaceSm),
      decoration: BoxDecoration(
        color: selected
            ? KlychTheme.accent.withValues(alpha: 0.12)
            : KlychTheme.surface,
        borderRadius: BorderRadius.circular(KlychTheme.radiusMd),
        border: Border.all(
          color: selected ? KlychTheme.accent.withValues(alpha: 0.5) : KlychTheme.borderSubtle,
        ),
      ),
      child: onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(KlychTheme.radiusMd),
              child: content,
            )
          : content,
    );
  }
}

class KlychSectionHeader extends StatelessWidget {
  const KlychSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KlychTheme.spaceMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KlychTheme.labelCaps),
                if (subtitle != null) ...[
                  const SizedBox(height: KlychTheme.spaceXs),
                  Text(subtitle!, style: KlychTheme.bodyMedium),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class KlychPrimaryButton extends StatelessWidget {
  const KlychPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final background = color ?? KlychTheme.accent;
    // Pick the foreground that contrasts best with the button colour so light
    // fills (e.g. the green INFO button) don't get washed-out white text.
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.light
            ? KlychTheme.background
            : Colors.white;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
              )
            : Icon(icon ?? Icons.send_rounded, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.4),
          disabledForegroundColor: foreground.withValues(alpha: 0.7),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class KlychConnectionBadge extends StatelessWidget {
  const KlychConnectionBadge({super.key, required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: connected ? KlychTheme.online : KlychTheme.offline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: KlychTheme.spaceSm),
        Text(
          connected ? 'ONLINE' : 'OFFLINE',
          style: KlychTheme.labelSmall.copyWith(
            color: connected ? KlychTheme.online : KlychTheme.offline,
          ),
        ),
      ],
    );
  }
}

class KlychEmptyState extends StatelessWidget {
  const KlychEmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(message, style: KlychTheme.bodyMedium),
    );
  }
}

class KlychFilterChip extends StatelessWidget {
  const KlychFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.selectedColor,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final color = selectedColor ?? KlychTheme.accent;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      backgroundColor: KlychTheme.surface,
      selectedColor: color.withValues(alpha: 0.2),
      checkmarkColor: color,
      labelStyle: KlychTheme.bodyMedium.copyWith(
        color: selected ? KlychTheme.textPrimary : KlychTheme.textSecondary,
        fontSize: 12,
      ),
      side: BorderSide(
        color: selected ? color.withValues(alpha: 0.6) : KlychTheme.borderSubtle,
      ),
      padding: const EdgeInsets.symmetric(horizontal: KlychTheme.spaceXs),
      visualDensity: VisualDensity.compact,
    );
  }
}

class KlychBrandMark extends StatelessWidget {
  const KlychBrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: KlychTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(KlychTheme.radiusMd),
        border: Border.all(color: KlychTheme.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Text(
        'K',
        style: TextStyle(
          color: KlychTheme.accent,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
      ),
    );
  }
}

class KlychSearchField extends StatelessWidget {
  const KlychSearchField({
    super.key,
    required this.controller,
    this.hint = 'Пошук за позивним...',
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: KlychTheme.bodyLarge.copyWith(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20, color: KlychTheme.textMuted),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18, color: KlychTheme.textMuted),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KlychTheme.spaceMd,
          vertical: KlychTheme.spaceSm,
        ),
      ),
    );
  }
}

class RecipientPreviewPanel extends StatelessWidget {
  const RecipientPreviewPanel({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Text(
      count == 0 ? 'ОТРИМУВАЧІ (0)' : '$count отримувачів обрано',
      style: KlychTheme.titleMedium.copyWith(fontSize: 14),
    );
  }
}

class KlychAppHeader extends StatelessWidget {
  const KlychAppHeader({
    super.key,
    required this.organization,
    required this.callsign,
    this.connected,
    this.trailing,
    this.brandSize = 52,
  });

  final String organization;
  final String callsign;

  /// When provided, the online/offline indicator is rendered inside the
  /// identity block (logo · organization · callsign) as a single header group.
  final bool? connected;
  final List<Widget>? trailing;
  final double brandSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        KlychBrandMark(size: brandSize),
        const SizedBox(width: KlychTheme.spaceMd),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('KLYCH', style: KlychTheme.displayLarge.copyWith(fontSize: 22)),
              if (organization.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  organization,
                  style: KlychTheme.bodyMedium.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      callsign.toUpperCase(),
                      style: KlychTheme.titleMedium.copyWith(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (connected != null) ...[
                    const SizedBox(width: KlychTheme.spaceMd),
                    KlychConnectionBadge(connected: connected!),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (trailing != null) ...trailing!,
      ],
    );
  }
}

class AlertLevelSelector extends StatelessWidget {
  const AlertLevelSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  Color _colorFor(String level) =>
      level == AlertLevel.green ? KlychTheme.alertGreen : KlychTheme.alertRed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KlychTheme.spaceMd, vertical: 2),
      decoration: BoxDecoration(
        color: KlychTheme.surface,
        borderRadius: BorderRadius.circular(KlychTheme.radiusMd),
        border: Border.all(color: KlychTheme.borderSubtle),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: KlychTheme.surfaceElevated,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: KlychTheme.textMuted, size: 18),
          style: KlychTheme.bodyLarge.copyWith(fontSize: 13),
          items: AlertLevel.labels.entries.map((e) {
            return DropdownMenuItem(
              value: e.key,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colorFor(e.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: KlychTheme.spaceSm),
                  Text(e.value),
                ],
              ),
            );
          }).toList(),
          selectedItemBuilder: (context) => AlertLevel.labels.entries.map((e) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _colorFor(e.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: KlychTheme.spaceSm),
                  Text(e.value, style: KlychTheme.bodyLarge.copyWith(fontSize: 13)),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

class KlychAlertHistoryTile extends StatelessWidget {
  const KlychAlertHistoryTile({
    super.key,
    required this.message,
    required this.subtitle,
    required this.isGreen,
    this.onTap,
  });

  final String message;
  final String subtitle;
  final bool isGreen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return KlychCard(
      onTap: onTap,
      padding: const EdgeInsets.all(KlychTheme.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinkifiedText(
            text: message,
            style: KlychTheme.titleMedium.copyWith(fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KlychTheme.spaceXs),
          Text(
            subtitle,
            style: KlychTheme.bodyMedium.copyWith(
              fontSize: 11,
              color: isGreen ? KlychTheme.alertGreen : KlychTheme.alertRed,
            ),
          ),
        ],
      ),
    );
  }
}
