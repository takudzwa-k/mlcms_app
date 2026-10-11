import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/fridge.dart';
import '../services/history.dart';

/// Listens to the last 24 hours of readings for every unit in [fridges]
/// and calls [builder] whenever anything changes.
class HistoryBuilder extends StatefulWidget {
  final List<Fridge> fridges;
  final Widget Function(
    BuildContext context,
    Map<String, List<Reading>> history,
    bool loading,
  ) builder;

  const HistoryBuilder({
    super.key,
    required this.fridges,
    required this.builder,
  });

  @override
  State<HistoryBuilder> createState() => _HistoryBuilderState();
}

class _HistoryBuilderState extends State<HistoryBuilder> {
  final _subs = <String, StreamSubscription<DatabaseEvent>>{};
  final _data = <String, List<Reading>>{};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HistoryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }

  // Keeps one live listener per unit
  void _sync() {
    final ids = widget.fridges.map((f) => f.id).toSet();

    for (final id in _subs.keys.where((id) => !ids.contains(id)).toList()) {
      _subs.remove(id)?.cancel();
      _data.remove(id);
    }

    final cutoff =
        DateTime.now().millisecondsSinceEpoch - 24 * 60 * 60 * 1000;

    for (final id in ids) {
      if (_subs.containsKey(id)) continue;

      final query = FirebaseDatabase.instance
          .ref('readings/$id')
          .orderByChild('t')
          .startAt(cutoff);

      _subs[id] = query.onValue.listen(
        (event) {
          if (!mounted) return;
          setState(() => _data[id] = parseReadings(event.snapshot.value));
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _data[id] = <Reading>[]);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.fridges.any((f) => !_data.containsKey(f.id));
    return widget.builder(context, Map.of(_data), loading);
  }
}