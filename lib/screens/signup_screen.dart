import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  String _role = 'technician';
  String? _error;

  Future<void> _signUp() async {
    try {
      await _authService.signUp(_emailController.text.trim(), _passwordController.text.trim(), _role);
    } catch (e) {
      setState(() => _error = 'Sign up failed: ${e.toString()}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email')),
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            DropdownButton<String>(
              value: _role,
              items: const [
                DropdownMenuItem(value: 'technician', child: Text('Technician')),
                DropdownMenuItem(value: 'supervisor', child: Text('Supervisor')),
              ],
              onChanged: (val) => setState(() => _role = val!),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            ElevatedButton(onPressed: _signUp, child: const Text('Sign Up')),
          ],
        ),
      ),
    );
  }
}