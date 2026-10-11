import 'package:flutter/material.dart';
import '../services/fridge_service.dart';
import '../models/fridge.dart';
import '../theme/app_theme.dart';
import 'add_fridge_screen.dart';
import 'fridge_detail_screen.dart';

class ManageFridgesScreen extends StatelessWidget {
  const ManageFridgesScreen({super.key});

  bool _isOnline(Fridge f) {
    if (f.lastSeen == 0) return false;
    final lastSeenTime = DateTime.fromMillisecondsSinceEpoch(f.lastSeen);
    return DateTime.now().difference(lastSeenTime).inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    final fridgeService = FridgeService();

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Fridges')),
      body: StreamBuilder<List<Fridge>>(
        stream: fridgeService.fridgesStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No fridges registered yet.\nTap + to add your first unit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15),
                ),
              ),
            );
          }

          final fridges = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  fridges.length == 1
                      ? '1 registered unit'
                      : '${fridges.length} registered units',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ),
              ...fridges.map(
                (f) => _FridgeTile(
                  fridge: f,
                  online: _isOnline(f),
                  onDelete: () => _confirmDelete(context, fridgeService, f),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddFridgeScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _confirmDelete(BuildContext context, FridgeService service, Fridge fridge) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Remove fridge?'),
        content: Text(
          '"${fridge.name}" will be removed from the system. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await service.deleteFridge(fridge.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _FridgeTile extends StatelessWidget {
  final Fridge fridge;
  final bool online;
  final VoidCallback onDelete;

  const _FridgeTile({
    required this.fridge,
    required this.online,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = online ? AppColors.ok : Colors.grey;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FridgeDetailScreen(fridge: fridge)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.tealLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.kitchen_outlined, color: AppColors.teal),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fridge.name,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fridge.location,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          online ? 'Live' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${fridge.minTemp}°C to ${fridge.maxTemp}°C',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}