import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../screens/manage_fridges_screen.dart';
import '../screens/account_screen.dart';
import '../screens/settings_screen.dart';
import 'surfaces.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.pop(context); // close the drawer first
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final padding = MediaQuery.of(context).padding;
    final line = dark ? Colors.white12 : const Color(0xFFE3E8E4);

    return Drawer(
      shape: const RoundedRectangleBorder(), // square edges
      backgroundColor: dark ? const Color(0xFF111F22) : Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Column(
        children: [
          // Tinted top section: logo, close button and the signed-in user
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, padding.top + 14, 16, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const [Color(0xFF15383B), Color(0xFF112A2D)]
                    : const [Color(0xFFD3E9E3), Color(0xFFE6F3EF)],
              ),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.teal.withAlpha(dark ? 70 : 45),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/logo_fridge.png',
                      height: 30,
                      errorBuilder: (context, error, stack) => const Icon(
                        Icons.kitchen_rounded,
                        size: 28,
                        color: AppColors.teal,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'MLCMS',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    const _CloseButton(),
                  ],
                ),
                const SizedBox(height: 18),
                const _UserBlock(),
              ],
            ),
          ),

          // Menu items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _DrawerItem(
                  icon: Icons.person_outline,
                  title: 'Account Details',
                  subtitle: 'Profile and access information',
                  onTap: () => _open(context, const AccountScreen()),
                ),
                _DrawerItem(
                  icon: Icons.tune,
                  title: 'Settings',
                  subtitle: 'Temperature units and appearance',
                  onTap: () => _open(context, const SettingsScreen()),
                ),
                _DrawerItem(
                  icon: Icons.kitchen_outlined,
                  title: 'Manage Fridges',
                  subtitle: 'Register and review equipment',
                  onTap: () => _open(context, const ManageFridgesScreen()),
                ),
              ],
            ),
          ),

          // Sign out, pinned to the bottom
          Divider(height: 1, color: line),
          Padding(
            padding: EdgeInsets.only(top: 6, bottom: padding.bottom + 6),
            child: _DrawerItem(
              icon: Icons.logout,
              title: 'Sign Out',
              subtitle: 'End this session',
              danger: true,
              onTap: () {
                Navigator.pop(context);
                AuthService().signOut();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface(context),
        shape: BoxShape.circle,
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => Navigator.pop(context),
          child: const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.close, size: 18),
          ),
        ),
      ),
    );
  }
}

/// The signed-in user. It listens to the database, so a name
/// changed on the Account screen shows up here straight away.
class _UserBlock extends StatelessWidget {
  const _UserBlock();

  static const _titles = {'dr', 'dr.', 'mr', 'mr.', 'mrs', 'mrs.', 'ms', 'ms.', 'prof', 'prof.'};

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('users/${user.uid}').onValue,
      builder: (context, snapshot) {
        final raw = snapshot.data?.snapshot.value;
        final data = raw is Map ? raw : const {};

        final fullName = (data['name'] ?? '').toString().trim();
        final role = (data['role'] ?? '').toString();
        final email = user.email ?? '';

        final parts = fullName
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty && !_titles.contains(p.toLowerCase()))
            .toList();

        final shownName = fullName.isNotEmpty ? fullName : email.split('@').first;
        final initials = parts.isNotEmpty
            ? parts.take(3).map((p) => p[0].toUpperCase()).join()
            : (email.isNotEmpty
                ? email.substring(0, email.length >= 2 ? 2 : 1).toUpperCase()
                : '?');
        final roleLabel = role.isEmpty ? '' : role[0].toUpperCase() + role.substring(1);

        return Row(
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.teal,
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  if (roleLabel.isNotEmpty)
                    Text(
                      roleLabel,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  const _DrawerItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = danger ? AppColors.danger : AppColors.teal;
    final tile = danger
        ? (dark ? AppColors.danger.withAlpha(40) : AppColors.dangerLight)
        : (dark ? Colors.white10 : AppColors.selected);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tile,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: danger ? AppColors.danger : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: danger
                          ? AppColors.danger.withAlpha(170)
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (!danger)
              Icon(Icons.chevron_right, size: 20, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }
}