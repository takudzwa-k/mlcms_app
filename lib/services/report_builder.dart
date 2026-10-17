import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'history.dart';

/// Everything the PDF needs, loaded once by the report screen.
class ReportData {
  final DateTime generatedAt;
  final String generatedBy;
  final String role;
  final List<UnitStats> stats;
  final Map<String, List<Reading>> readings;
  final int? demoAt; // set when the history was made by the Demo tools

  const ReportData({
    required this.generatedAt,
    required this.generatedBy,
    required this.role,
    required this.stats,
    required this.readings,
    required this.demoAt,
  });
}

final _teal = PdfColor.fromInt(0xFF08766D);
final _ok = PdfColor.fromInt(0xFF307C68);
final _danger = PdfColor.fromInt(0xFFBC5050);
final _warn = PdfColor.fromInt(0xFFAC7428);
final _ink = PdfColor.fromInt(0xFF16262B);
final _grey = PdfColor.fromInt(0xFF6B7470);
final _tint = PdfColor.fromInt(0xFFEAF3F0);
final _zebra = PdfColor.fromInt(0xFFF6F7F3);
final _pink = PdfColor.fromInt(0xFFFBE4E1);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

// ---------- Formatting ----------

String _two(int n) => n.toString().padLeft(2, '0');

String _signed(double v, [int digits = 1]) =>
    '${v >= 0 ? '+' : ''}${v.toStringAsFixed(digits)}';

String _limit(double v) {
  final text = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${v >= 0 ? '+' : ''}$text°C';
}

String _stamp(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day} ${_months[d.month - 1]} ${_two(d.hour)}:${_two(d.minute)}';
}

String _fullStamp(DateTime d) =>
    '${d.day} ${_months[d.month - 1]} ${d.year}, ${_two(d.hour)}:${_two(d.minute)}';

String _duration(int minutes) {
  if (minutes < 1) return '<1 min';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

PdfColor _uptimeColor(double pct) =>
    pct >= 95 ? _ok : (pct >= 85 ? _warn : _danger);

// ---------- Building blocks ----------

pw.Widget _cell(
  String text, {
  bool bold = false,
  PdfColor? color,
  bool right = false,
  double size = 8.5,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    child: pw.Align(
      alignment: right ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? _ink,
        ),
      ),
    ),
  );
}

pw.TableRow _headerRow(List<String> labels, {Set<int> rightCols = const {}}) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: _tint),
    children: [
      for (var i = 0; i < labels.length; i++)
        _cell(labels[i],
            bold: true, color: _teal, size: 8, right: rightCols.contains(i)),
    ],
  );
}

pw.Widget _table(Map<int, pw.TableColumnWidth> widths, List<pw.TableRow> rows) {
  return pw.Table(
    columnWidths: widths,
    defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
    children: rows,
  );
}

pw.Widget _section(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 12,
        fontWeight: pw.FontWeight.bold,
        color: _teal,
      ),
    ),
  );
}

pw.Widget _stat(String label, String value, PdfColor color, String caption) {
  return pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(right: 8),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: _tint,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: _grey,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(caption, style: pw.TextStyle(fontSize: 8, color: _grey)),
        ],
      ),
    ),
  );
}

pw.Widget _meta(ReportData d) {
  final end = d.generatedAt;
  final periodStart = end.subtract(const Duration(hours: 24));
  final role = d.role.isEmpty ? '' : ' (${_cap(d.role)})';

  pw.Widget line(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 82,
            child: pw.Text(key, style: pw.TextStyle(fontSize: 9, color: _grey)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: pw.TextStyle(fontSize: 9, color: _ink)),
          ),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      line('Generated', _fullStamp(end)),
      line('Generated by', '${d.generatedBy}$role'),
      line('Period', 'Last 24 hours (${_fullStamp(periodStart)} to ${_fullStamp(end)})'),
      line('Data source', 'Readings stored in the MLCMS database'),
    ],
  );
}

pw.Widget _demoBanner(int demoAt) {
  return pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      color: _pink,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Text(
      'DEMO DATA: this database holds simulated history generated with the Demo tools on '
      '${_fullStamp(DateTime.fromMillisecondsSinceEpoch(demoAt))}. '
      'Do not use this report as a record.',
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: _danger,
      ),
    ),
  );
}

// ---------- Tables ----------

pw.Widget _unitTable(ReportData d) {
  final rows = <pw.TableRow>[
    _headerRow(
      ['Unit', 'Safe range', 'Now', 'In range', 'Avg', 'Min', 'Max', 'Incid.'],
      rightCols: {2, 3, 4, 5, 6, 7},
    ),
  ];

  for (var i = 0; i < d.stats.length; i++) {
    final s = d.stats[i];
    final f = s.fridge;
    final rs = d.readings[f.id] ?? const <Reading>[];

    double? lo;
    double? hi;
    for (final r in rs) {
      if (lo == null || r.temp < lo) lo = r.temp;
      if (hi == null || r.temp > hi) hi = r.temp;
    }

    rows.add(
      pw.TableRow(
        decoration: i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  f.name,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.Text(
                  f.location,
                  style: pw.TextStyle(fontSize: 7.5, color: _grey),
                ),
              ],
            ),
          ),
          _cell('${_limit(f.minTemp)} to ${_limit(f.maxTemp)}'),
          _cell(
            f.hasData ? '${_signed(f.temperature)}°C' : '--',
            bold: true,
            color: !f.hasData ? _grey : (f.inRange ? _ok : _danger),
            right: true,
          ),
          _cell(
            s.hasHistory ? '${s.percentInRange.toStringAsFixed(1)}%' : '--',
            bold: true,
            color: s.hasHistory ? _uptimeColor(s.percentInRange) : _grey,
            right: true,
          ),
          _cell(s.hasHistory ? '${_signed(s.avgTemp)}°C' : '--', right: true),
          _cell(lo == null ? '--' : '${_signed(lo)}°C', right: true),
          _cell(hi == null ? '--' : '${_signed(hi)}°C', right: true),
          _cell(s.hasHistory ? '${s.incidents.length}' : '--', right: true),
        ],
      ),
    );
  }

  return _table({
    0: pw.FlexColumnWidth(3.2),
    1: pw.FlexColumnWidth(2.4),
    2: pw.FlexColumnWidth(1.4),
    3: pw.FlexColumnWidth(1.5),
    4: pw.FlexColumnWidth(1.4),
    5: pw.FlexColumnWidth(1.4),
    6: pw.FlexColumnWidth(1.4),
    7: pw.FlexColumnWidth(1.1),
  }, rows);
}

pw.Widget _incidentTable(ReportData d, int nowMs) {
  final all = [for (final s in d.stats) ...s.incidents]
    ..sort((a, b) {
      if (a.open != b.open) return a.open ? -1 : 1;
      return b.startMs.compareTo(a.startMs);
    });

  if (all.isEmpty) {
    return pw.Text(
      'No incidents in the last 24 hours.',
      style: pw.TextStyle(fontSize: 9.5, color: _grey),
    );
  }

  final rows = <pw.TableRow>[
    _headerRow(['Unit', 'Started', 'Ended', 'Duration', 'Peak', 'Status']),
  ];

  for (var i = 0; i < all.length; i++) {
    final inc = all[i];
    final minutes =
        inc.open ? ((nowMs - inc.startMs) / 60000).round() : inc.minutes;

    rows.add(
      pw.TableRow(
        decoration: i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
        children: [
          _cell(inc.fridgeName, bold: true),
          _cell(_stamp(inc.startMs)),
          _cell(inc.open ? 'Ongoing' : _stamp(inc.endMs)),
          _cell(_duration(minutes)),
          _cell('${_signed(inc.peak)}°C ${inc.above ? '(high)' : '(low)'}'),
          _cell(
            inc.open ? 'Open' : 'Resolved',
            bold: true,
            color: inc.open ? _danger : _ok,
          ),
        ],
      ),
    );
  }

  return _table({
    0: pw.FlexColumnWidth(2.6),
    1: pw.FlexColumnWidth(1.7),
    2: pw.FlexColumnWidth(1.7),
    3: pw.FlexColumnWidth(1.3),
    4: pw.FlexColumnWidth(1.9),
    5: pw.FlexColumnWidth(1.2),
  }, rows);
}

List<pw.Widget> _readingsLog(ReportData d) {
  final widgets = <pw.Widget>[
    _section('Readings log (every stored reading, last 24 hours)'),
  ];

  for (final s in d.stats) {
    final f = s.fridge;
    final rs = d.readings[f.id] ?? const <Reading>[];

    widgets.add(pw.SizedBox(height: 12));
    widgets.add(
      pw.Text(
        '${f.name} (${f.location}) - safe range ${_limit(f.minTemp)} to ${_limit(f.maxTemp)}',
        style: pw.TextStyle(
          fontSize: 9.5,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    );
    widgets.add(pw.SizedBox(height: 4));

    if (rs.isEmpty) {
      widgets.add(
        pw.Text(
          'No readings stored.',
          style: pw.TextStyle(fontSize: 9, color: _grey),
        ),
      );
      continue;
    }

    final rows = <pw.TableRow>[
      _headerRow(
        ['Time', 'Temperature', 'Humidity', 'Door', 'Range'],
        rightCols: {1, 2},
      ),
    ];

    for (var i = 0; i < rs.length; i++) {
      final r = rs[i];
      final outside = r.temp < f.minTemp || r.temp > f.maxTemp;

      rows.add(
        pw.TableRow(
          decoration: i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
          children: [
            _cell(_stamp(r.t), size: 8),
            _cell(
              '${r.temp.toStringAsFixed(1)}°C',
              size: 8,
              right: true,
              color: outside ? _danger : null,
            ),
            _cell('${r.hum.round()}%', size: 8, right: true),
            _cell(r.door ? 'Open' : 'Closed', size: 8),
            _cell(
              outside ? 'Outside' : 'In range',
              size: 8,
              color: outside ? _danger : _ok,
            ),
          ],
        ),
      );
    }

    widgets.add(
      _table({
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.2),
        4: pw.FlexColumnWidth(1.4),
      }, rows),
    );
  }

  return widgets;
}

// ---------- The document ----------

Future<pw.MemoryImage?> _loadLogo() async {
  try {
    final bytes = await rootBundle.load('assets/images/logo_fridge.png');
    return pw.MemoryImage(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  } catch (_) {
    return null; // the report still works without the logo
  }
}

Future<Uint8List> buildReportPdf(
  ReportData d, {
  bool includeReadings = false,
}) async {
  final nowMs = d.generatedAt.millisecondsSinceEpoch;
  final logo = await _loadLogo();

  final withHistory = d.stats.where((s) => s.hasHistory).toList();
  final uptime = withHistory.isEmpty
      ? null
      : withHistory.fold<double>(0, (a, s) => a + s.percentInRange) /
          withHistory.length;
  final incidents = [for (final s in d.stats) ...s.incidents];
  final open = incidents.where((i) => i.open).length;
  final alerts = d.stats.where((s) => s.fridge.isBreaching).length;

  final doc = pw.Document(
    title: 'MLCMS cold-chain report',
    author: d.generatedBy,
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 44),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          'MLCMS report - page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: _grey),
        ),
      ),
      build: (ctx) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Image(logo, height: 40),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Cold-chain report',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'MLCMS - Malaria Cold Chain Monitoring System',
                    style: pw.TextStyle(fontSize: 9.5, color: _grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        if (d.demoAt != null) _demoBanner(d.demoAt!),
        _meta(d),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            _stat(
              'FLEET UPTIME',
              uptime == null ? '--' : '${uptime.toStringAsFixed(1)}%',
              uptime == null ? _grey : _uptimeColor(uptime),
              uptime == null ? 'no history yet' : 'avg time in range',
            ),
            _stat(
              'INCIDENTS',
              '${incidents.length}',
              _ink,
              '${incidents.length - open} resolved, $open open',
            ),
            _stat(
              'ACTIVE ALERTS',
              '$alerts',
              alerts > 0 ? _danger : _ok,
              alerts > 0 ? 'currently breaching' : 'all clear',
            ),
            _stat(
              'UNITS',
              '${d.stats.length}',
              _ink,
              '${withHistory.length} with history',
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        _section('Unit summary'),
        _unitTable(d),
        pw.SizedBox(height: 18),
        _section('Incidents (last 24 hours)'),
        _incidentTable(d, nowMs),
        pw.SizedBox(height: 18),
        pw.Text(
          'Percentages and incidents are calculated from the readings stored in the last '
          '24 hours, measured against the current safe range of each unit. An incident is '
          'one continuous period outside the safe range; Open means the unit was still '
          'outside it at the latest reading. Times come from the clock of the device that '
          'recorded or exported the data. This report is generated by the app and is not a '
          'tamper-proof record.',
          style: pw.TextStyle(fontSize: 8, color: _grey, lineSpacing: 2),
        ),
        if (includeReadings) pw.NewPage(),
        if (includeReadings) ..._readingsLog(d),
      ],
    ),
  );

  return doc.save();
}