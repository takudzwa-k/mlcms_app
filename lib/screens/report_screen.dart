import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import '../services/auth_service.dart';
import '../services/fridge_service.dart';
import '../services/history.dart';
import '../services/report_builder.dart';
import '../theme/app_theme.dart';
import '../widgets/surfaces.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String _fileName(DateTime d) =>
    'MLCMS_report_${d.year}-${_two(d.month)}-${_two(d.day)}_${_two(d.hour)}${_two(d.minute)}.pdf';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late final Future<ReportData> _future = _load();
  bool _includeReadings = false;

  Future<ReportData> _load() async {
    final db = FirebaseDatabase.instance.ref();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final cutoff = nowMs - 24 * 60 * 60 * 1000;

    final fridges = await FridgeService().fridgesStream.first;
    fridges.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // the last 24 hours of readings for every unit
    final lists = await Future.wait(
      fridges.map((f) async {
        final snap = await db
            .child('readings/${f.id}')
            .orderByChild('t')
            .startAt(cutoff)
            .get();
        return parseReadings(snap.value);
      }),
    );

    // who is exporting the report
    var by = 'Unknown user';
    var role = '';
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      by = user.email ?? 'Unknown user';
      try {
        final data = await AuthService().getUserData(user.uid);
        final name = (data?['name'] ?? '').toString().trim();
        if (name.isNotEmpty) by = name;
        role = (data?['role'] ?? '').toString();
      } catch (_) {
        // keep the email as the name
      }
    }

    // was the history made with the Demo tools?
    int? demoAt;
    try {
      final snap = await db.child('readings/_demo').get();
      final v = snap.value;
      if (v is num) demoAt = v.toInt();
    } catch (_) {
      // treat as real data
    }

    final readings = {
      for (var i = 0; i < fridges.length; i++) fridges[i].id: lists[i],
    };
    final stats = [
      for (final f in fridges)
        computeStats(f, readings[f.id] ?? const <Reading>[], nowMs),
    ];

    return ReportData(
      generatedAt: now,
      generatedBy: by,
      role: role,
      stats: stats,
      readings: readings,
      demoAt: demoAt,
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export report')),
      body: FutureBuilder<ReportData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || snap.data == null) {
            return _message(
              'Could not load the data for the report.\nCheck your connection and try again.',
            );
          }

          final data = snap.data!;
          if (data.stats.isEmpty) {
            return _message('No fridges yet.\nAdd a unit before exporting a report.');
          }

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                decoration: BoxDecoration(
                  color: appSurface(context),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: softShadow(context),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'Include full readings log',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Adds every stored reading from the last 24 hours (many pages).',
                        ),
                        value: _includeReadings,
                        activeColor: AppColors.teal,
                        onChanged: (v) => setState(() => _includeReadings = v),
                      ),
                      if (data.demoAt != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warnLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'This history was generated with the Demo tools, so the PDF '
                              'will carry a "DEMO DATA" notice. Clear it in Settings once '
                              'real readings arrive.',
                              style: TextStyle(
                                color: AppColors.warn,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: PdfPreview(
                  key: ValueKey(_includeReadings),
                  build: (format) =>
                      buildReportPdf(data, includeReadings: _includeReadings),
                  pdfFileName: _fileName(data.generatedAt),
                  initialPageFormat: PdfPageFormat.a4,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  actionBarTheme: const PdfActionBarTheme(
                    backgroundColor: AppColors.teal,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}