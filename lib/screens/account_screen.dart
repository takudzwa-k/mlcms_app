import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _authService = AuthService();
  final _nameController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String _email = '';
  String _role = '';
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = await _authService.getUserData(user.uid);
    setState(() {
      _email = data?['email'] ?? user.email ?? '';
      _role = data?['role'] ?? 'technician';
      _nameController.text = data?['name'] ?? '';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      await _authService.updateDisplayName(user.uid, _nameController.text.trim());
      setState(() {
        _saving = false;
        _message = 'Saved!';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _message = 'Failed to save';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Text(
                  _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 28, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              enabled: false,
              controller: TextEditingController(text: _role[0].toUpperCase() + _role.substring(1)),
              decoration: const InputDecoration(labelText: 'Role (read-only)'),
            ),
            const SizedBox(height: 16),
            TextField(
              enabled: false,
              controller: TextEditingController(text: _email),
              decoration: const InputDecoration(labelText: 'Email (read-only)'),
            ),
            const SizedBox(height: 20),
            if (_message != null)
              Text(_message!, style: TextStyle(color: _message == 'Saved!' ? Colors.green : Colors.red)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}