import 'package:flutter/material.dart';
import '../services/fridge_service.dart';

class AddFridgeScreen extends StatefulWidget {
  const AddFridgeScreen({super.key});

  @override
  State<AddFridgeScreen> createState() => _AddFridgeScreenState();
}

class _AddFridgeScreenState extends State<AddFridgeScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _minTempController = TextEditingController();
  final _maxTempController = TextEditingController();
  final _fridgeService = FridgeService();

  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    // Basic validation
    if (_nameController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty ||
        _minTempController.text.trim().isEmpty ||
        _maxTempController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in all fields');
      return;
    }

    final minTemp = double.tryParse(_minTempController.text.trim());
    final maxTemp = double.tryParse(_maxTempController.text.trim());

    if (minTemp == null || maxTemp == null) {
      setState(() => _error = 'Min/Max temperature must be numbers');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _fridgeService.addFridge(
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        minTemp: minTemp,
        maxTemp: maxTemp,
      );
      if (mounted) Navigator.pop(context); // go back to previous screen
    } catch (e) {
      setState(() {
        _saving = false;
        _error = 'Failed to save: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Fridge')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Fridge Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Location'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minTempController,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Min Temp (°C)'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _maxTempController,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    decoration: const InputDecoration(labelText: 'Max Temp (°C)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Fridge'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}