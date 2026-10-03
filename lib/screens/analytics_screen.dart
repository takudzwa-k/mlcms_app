import 'package:flutter/material.dart';
import '../services/fridge_service.dart';
import '../models/fridge.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  bool _isOnline(Fridge f) {
    final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(f.lastSeen);
    return DateTime.now().difference(lastSeenTime).inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    final fridgeService = FridgeService();

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: StreamBuilder<List<Fridge>>(
        stream: fridgeService.fridgesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No fridges to analyze yet'));
          }

          final fridges = snapshot.data!;
          final total = fridges.length;
          final inRange = fridges.where((f) => f.inRange).length;
          final breaching = total - inRange;
          final online = fridges.where(_isOnline).length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Live snapshot \u2014 ${DateTime.now().toString().substring(0, 16)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _statCard('Total Units', '$total', Colors.blueGrey)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('Online', '$online/$total', Colors.teal)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _statCard('In Range', '$inRange', Colors.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _statCard('Breaching', '$breaching', Colors.red)),
                ],
              ),
              const SizedBox(height: 24),
              Text('Unit Breakdown', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 8),
              ...fridges.map((f) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(f.name),
                      subtitle: Text(f.location),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${f.temperature.toStringAsFixed(1)}°C',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: f.inRange ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                          Text(
                            _isOnline(f) ? 'Online' : 'Offline',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}