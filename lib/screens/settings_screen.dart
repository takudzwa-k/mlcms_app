import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.useFahrenheit,
            builder: (context, useFahrenheit, _) {
              return SwitchListTile(
                title: const Text('Use Fahrenheit (°F)'),
                subtitle: const Text('Default is Celsius (°C)'),
                value: useFahrenheit,
                onChanged: (value) => AppSettings.useFahrenheit.value = value,
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.darkMode,
            builder: (context, isDark, _) {
              return SwitchListTile(
                title: const Text('Dark Mode'),
                value: isDark,
                onChanged: (value) => AppSettings.darkMode.value = value,
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
            onTap: () => AuthService().signOut(),
          ),
        ],
      ),
    );
  }
}