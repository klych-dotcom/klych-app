import 'package:flutter/material.dart';

import '../main.dart';
import '../models/user_role.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool loading = true;

  List<Map<String, dynamic>> users = [];

  @override
  void initState() {
    super.initState();

    loadUsers();
  }

  Future<void> loadUsers() async {
    try {
      final currentUser = supabase.auth.currentUser;

      if (currentUser == null) return;

      final userData = await supabase
          .from('users')
          .select()
          .eq('auth_id', currentUser.id)
          .single();

      final organizationId = userData['organization_id'];

      final response = await supabase
          .from('users')
          .select()
          .eq('organization_id', organizationId)
          .order('created_at', ascending: false);

      users = List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('$e');
    }

    if (!mounted) return;

    setState(() {
      loading = false;
    });
  }

  Color getRoleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.red;

      case 'leader':
        return Colors.orange;

      case 'medic':
        return Colors.green;

      case 'driver':
        return Colors.blue;

      default:
        return Colors.white54;
    }
  }

  IconData getRoleIcon(String role) {
    switch (role) {
      case 'admin':
        return Icons.shield_rounded;

      case 'leader':
        return Icons.star_rounded;

      case 'medic':
        return Icons.medical_services_rounded;

      case 'driver':
        return Icons.directions_car_rounded;

      default:
        return Icons.person;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F10),

      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F10),
        elevation: 0,

        iconTheme: const IconThemeData(color: Colors.white),

        title: const Text(
          'КОРИСТУВАЧІ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.red))
          : users.isEmpty
          ? const Center(
              child: Text(
                'Немає користувачів',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),

              itemCount: users.length,

              itemBuilder: (_, index) {
                final user = users[index];

                final role = UserRole.resolve(user);

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),

                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: BorderRadius.circular(22),
                  ),

                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,

                        decoration: BoxDecoration(
                          color: getRoleColor(role).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                        ),

                        child: Icon(
                          getRoleIcon(role),
                          color: getRoleColor(role),
                        ),
                      ),

                      const SizedBox(width: 16),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,

                          children: [
                            Text(
                              (user['callsign'] ?? 'UNKNOWN').toUpperCase(),

                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 4),

                            Text(
                              role.toUpperCase(),

                              style: TextStyle(
                                color: getRoleColor(role),
                                fontSize: 13,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
