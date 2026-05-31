import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../screens/home_screen.dart';
import '../screens/leader_home_screen.dart';
import '../screens/member_home_screen.dart';

/// Returns the home widget for a resolved role string.
Widget homeScreenForRole(String role) {
  if (UserRole.isAdmin(role)) return const HomeScreen();
  if (UserRole.isLeader(role)) return const LeaderHomeScreen();
  return const MemberHomeScreen();
}

/// Replaces the navigation stack with the role-appropriate home screen.
void navigateToRoleHome(BuildContext context, String role) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => homeScreenForRole(role)),
    (route) => false,
  );
}
