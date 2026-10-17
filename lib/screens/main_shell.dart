import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/alert_state.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'alerts_screen.dart';
import 'analytics_screen.dart';
import 'thresholds_screen.dart';
import '../services/notification_service.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0;

  // Plays a quick fade each time the tab changes
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1.0,
  );
  late final Animation<double> _fadeCurve =
      CurvedAnimation(parent: _fade, curve: Curves.easeOut);

  static const _screens = [
    DashboardScreen(),
    AlertsScreen(),
    AnalyticsScreen(),
    ThresholdsScreen(),
  ];
    
    @override
    void initState() {
      super.initState();
      NotificationService.start(); // subscribes this phone to alerts
    }  

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = i);
    if (!MediaQuery.of(context).disableAnimations) {
      _fade.forward(from: 0.25);
    }
  }

  Widget _alertIcon(int count, IconData icon, {Color? color}) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      backgroundColor: AppColors.danger,
      child: Icon(icon, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: FadeTransition(
        opacity: _fadeCurve,
        child: IndexedStack(index: _index, children: _screens),
      ),
      // The badge shows how many alerts are unread
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: AlertState.unread,
        builder: (context, unread, _) {
          return NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            backgroundColor: isDark ? const Color(0xFF16272B) : AppColors.surface,
            indicatorColor: AppColors.tealLight,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded, color: AppColors.teal),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: _alertIcon(unread, Icons.notifications_outlined),
                selectedIcon: _alertIcon(
                  unread,
                  Icons.notifications,
                  color: AppColors.teal,
                ),
                label: 'Alerts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart_rounded, color: AppColors.teal),
                label: 'Analytics',
              ),
              const NavigationDestination(
                icon: Icon(Icons.tune),
                selectedIcon: Icon(Icons.tune, color: AppColors.teal),
                label: 'Thresholds',
              ),
            ],
          );
        },
      ),
    );
  }
}