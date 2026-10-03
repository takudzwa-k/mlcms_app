import 'package:flutter/material.dart';
import '../models/fridge.dart';
import '../services/fridge_service.dart';
import 'edit_fridge_screen.dart';

class FridgeDetailScreen extends StatelessWidget {
  final Fridge fridge;

  const FridgeDetailScreen({super.key, required this.fridge});

  bool _isLive(Fridge f) {
    final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(f.lastSeen);
    final difference = DateTime.now().difference(lastSeenTime);
    return difference.inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    final fridgeService = FridgeService();

    return StreamBuilder<Fridge?>(
      stream: fridgeService.fridgeStream(fridge.id),
      initialData: fridge, // show the data we already have instantly, then update live
      builder: (context, snapshot) {
        final liveFridge = snapshot.data ?? fridge;

        return Scaffold(
          appBar: AppBar(
            title: Text(liveFridge.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => EditFridgeScreen(fridge: liveFridge)),
                  );
                },
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(liveFridge.location, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _statusChip(
                      _isLive(liveFridge) ? 'Live' : 'Offline',
                      _isLive(liveFridge) ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 10),
                    _statusChip(
                      liveFridge.doorOpen ? 'Door Open' : 'Door Closed',
                      liveFridge.doorOpen ? Colors.orange : Colors.green,
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                Center(
                  child: Column(
                    children: [
                      Text(
                        '${liveFridge.temperature.toStringAsFixed(1)}°C',
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Humidity: ${liveFridge.humidity.toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Text('Safe Range', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Text('${liveFridge.minTemp}°C to ${liveFridge.maxTemp}°C', style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  liveFridge.inRange ? '✓ Currently within safe range' : '⚠ Currently outside safe range',
                  style: TextStyle(
                    color: liveFridge.inRange ? Colors.green.shade700 : Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}