import 'package:flutter/material.dart';
import '../models/fridge.dart';
import '../services/fridge_service.dart';
import '../theme/app_theme.dart';

class EditFridgeScreen extends StatefulWidget {
  final Fridge fridge;

  const EditFridgeScreen({super.key, required this.fridge});

  @override
  State<EditFridgeScreen> createState() => _EditFridgeScreenState();
}

class _EditFridgeScreenState extends State<EditFridgeScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _minTempController;
  late final TextEditingController _maxTempController;
  final _fridgeService = FridgeService();

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.fridge.name);
    _locationController = TextEditingController(text: widget.fridge.location);
    _minTempController = TextEditingController(text: widget.fridge.minTemp.toString());
    _maxTempController = TextEditingController(text: widget.fridge.maxTemp.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _minTempController.dispose();
    _maxTempController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty ||
        _minTempController.text.trim().isEmpty ||
        _maxTempController.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in every field.');
      return;
    }

    final minTemp = double.tryParse(_minTempController.text.trim());
    final maxTemp = double.tryParse(_maxTempController.text.trim());

    if (minTemp == null || maxTemp == null) {
      setState(() => _error = 'Min and max temperature must be numbers.');
      return;
    }
    if (minTemp >= maxTemp) {
      setState(() => _error = 'The minimum must be lower than the maximum.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _fridgeService.updateFridge(
        id: widget.fridge.id,
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        minTemp: minTemp,
        maxTemp: maxTemp,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your changes. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit fridge')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Fridge name',
                  prefixIcon: Icon(Icons.kitchen_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _locationController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'SAFE TEMPERATURE RANGE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minTempController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Min (°C)'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _maxTempController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Max (°C)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Read-only hardware info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.tealLight.withAlpha(90),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 18, color: AppColors.teal),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Device ID',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.fridge.id,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Linked to the physical sensor, so it can\'t be changed here.',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}