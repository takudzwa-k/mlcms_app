import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';
import '../services/demo_data.dart';
import '../services/fridge_service.dart';
import '../theme/app_theme.dart';
import '../widgets/surfaces.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isSupervisor = false;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      AuthService().getUserRole(user.uid).then((role) {
        if (mounted) setState(() => _isSupervisor = role == 'supervisor');
      }).catchError((_) {});
    }
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final fridges = await FridgeService().fridgesStream.first;
      final count = await DemoData.generate(fridges);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = count == 0
            ? 'No units have reported data yet, so nothing was generated.'
            : 'Wrote $count demo readings and marked the units live for 5 minutes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Could not write history. Check the database rules and your connection.';
      });
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await DemoData.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = false;
        _message = 'All history cleared.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _messageIsError = true;
        _message = 'Could not clear history. Check your connection and try again.';
      });
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: appSurface(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _sectionLabel('PREFERENCES'),
          _card(
            Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.useFahrenheit,
                  builder: (context, useFahrenheit, _) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.thermostat_outlined),
                      title: const Text('Use Fahrenheit (°F)'),
                      subtitle: const Text('Not applied to readings yet'),
                      value: useFahrenheit,
                      activeColor: AppColors.teal,
                      onChanged: (value) => AppSettings.useFahrenheit.value = value,
                    );
                  },
                ),
                const Divider(height: 1),
                ValueListenableBuilder<bool>(
                  valueListenable: AppSettings.darkMode,
                  builder: (context, isDark, _) {
                    return SwitchListTile(
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: const Text('Dark mode'),
                      value: isDark,
                      activeColor: AppColors.teal,
                      onChanged: (value) => AppSettings.darkMode.value = value,
                    );
                  },
                ),
              ],
            ),
          ),
          if (_isSupervisor) ...[
            const SizedBox(height: 28),
            _sectionLabel('DEMO TOOLS'),
            _card(
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Demo history',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fills every unit that has reported data with 24 hours of '
                      'simulated readings, so Analytics and Incidents have something '
                      'to show. Clear it once real readings start arriving.',
                      style: TextStyle(fontSize: 13, height: 1.35, color: Colors.grey.shade600),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: _messageIsError ? AppColors.dangerLight : AppColors.okLight,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _messageIsError ? AppColors.danger : AppColors.ok,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _busy ? null : _generate,
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Generate 24h demo history'),
                    ),
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : _clear,
                        child: const Text('Clear all history'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          _sectionLabel('SESSION'),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
              AuthService().signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}