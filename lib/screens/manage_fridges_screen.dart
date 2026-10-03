import 'package:flutter/material.dart';
import '../services/fridge_service.dart';
import '../models/fridge.dart';
import 'add_fridge_screen.dart';

class ManageFridgesScreen extends StatelessWidget {
  const ManageFridgesScreen({super.key});

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
            return const Center(child: Text('No fridges registered yet'));
          }

          final fridges = snapshot.data!;
          return ListView.builder(
            itemCount: fridges.length,
            itemBuilder: (context, index) {
              final fridge = fridges[index];
              return ListTile(
                title: Text(fridge.name),
                subtitle: Text(fridge.location),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context, fridgeService, fridge),
                ),
              );
            },
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
        title: const Text('Remove Fridge'),
        content: Text('Are you sure you want to remove "${fridge.name}"? This cannot be undone.'),
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
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}