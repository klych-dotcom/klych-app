/// Authorization roles only — admin, leader, member.
/// Legacy values (medic, driver) map to [member] for routing.
class UserRole {
  static const admin = 'admin';
  static const leader = 'leader';
  static const member = 'member';

  /// Legacy category values stored before department model.
  static const medic = 'medic';
  static const driver = 'driver';

  static const authorizationRoles = [admin, leader, member];

  /// Raw role from DB.
  static String resolveRaw(Map<String, dynamic> userData) {
    final role = userData['role']?.toString().trim().toLowerCase();
    if (role != null && role.isNotEmpty) return role;
    return member;
  }

  /// Authorization role used for routing and permissions.
  static String authorizationRole(Map<String, dynamic> userData) {
    final raw = resolveRaw(userData);
    if (raw == admin || raw == leader) return raw;
    return member;
  }

  static Map<String, String> toDbFields(String role) {
    final normalized = authorizationRole({'role': role});
    return {'role': normalized};
  }

  static bool isAdmin(String role) => authorizationRole({'role': role}) == admin;

  static bool isLeader(String role) =>
      authorizationRole({'role': role}) == leader;

  static bool usesMemberHome(Map<String, dynamic> userData) {
    final auth = authorizationRole(userData);
    return auth != admin && auth != leader;
  }
}
