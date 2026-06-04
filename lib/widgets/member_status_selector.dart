import 'package:flutter/material.dart';

import '../models/user_status.dart';

/// Compact operational status selector for member home.
class MemberStatusSelector extends StatelessWidget {
  const MemberStatusSelector({
    super.key,
    required this.selectedStatus,
    required this.onChanged,
    this.enabled = true,
  });

  final String selectedStatus;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ОПЕРАТИВНИЙ СТАТУС',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF252528),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: UserStatus.normalize(selectedStatus),
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A1C),
              icon: const Icon(Icons.expand_more, color: Colors.white54),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              items: UserStatus.all
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(UserStatus.label(status)),
                    ),
                  )
                  .toList(),
              onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
            ),
          ),
        ),
      ],
    );
  }
}
