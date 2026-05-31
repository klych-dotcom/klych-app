/// Role helpers — [role] is primary; [permission] kept for backward compatibility.
class UserRole {
  static const admin = 'admin';
  static const leader = 'leader';
  static const member = 'member';
  static const medic = 'medic';
  static const driver = 'driver';

  /// Reads role from a users row, preferring [role] over [permission].
  static String resolve(Map<String, dynamic> userData) {
    final role = userData['role']?.toString().trim().toLowerCase();
    if (role != null && role.isNotEmpty) return role;

    final permission = userData['permission']?.toString().trim().toLowerCase();
    if (permission != null && permission.isNotEmpty) return permission;

    return member;
  }

  /// DB payload with both columns in sync (temporary dual-write).
  static Map<String, String> toDbFields(String role) {
    final normalized = role.trim().toLowerCase();
    return {'role': normalized, 'permission': normalized};
  }

  static bool isAdmin(String role) => role.toLowerCase() == admin;

  static bool isLeader(String role) => role.toLowerCase() == leader;

  /// Admin and leader use dedicated shells; medic/driver/member share member UI.
  static bool usesMemberHome(String role) {
    final r = role.toLowerCase();
    return !isAdmin(r) && !isLeader(r);
  }
}
