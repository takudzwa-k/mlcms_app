import 'package:flutter/material.dart';
import '../services/fridge_service.dart';
import '../models/fridge.dart';
import 'fridge_detail_screen.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final fridgeService = FridgeService();

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: StreamBuilder<List<Fridge>>(
        stream: fridgeService.fridgesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('No data available'));
          }

          // Only show fridges currently outside their safe range
          final breaching = snapshot.data!.where((f) => !f.inRange).toList();

          if (breaching.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '✓ All clear — every unit is currently within its safe range.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.green),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: breaching.length,
            itemBuilder: (context, index) {
              final fridge = breaching[index];
              final isAboveRange = fridge.temperature > fridge.maxTemp;

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FridgeDetailScreen(fridge: fridge)),
                  );
                },
                child: Card(
                  color: Colors.red.shade50,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.red),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                fridge.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(fridge.location, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                        const SizedBox(height: 10),
                        Text(
                          '${fridge.temperature.toStringAsFixed(1)}°C',
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        Text(
                          isAboveRange
                              ? 'Above safe max of ${fridge.maxTemp}°C'
                              : 'Below safe min of ${fridge.minTemp}°C',
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}