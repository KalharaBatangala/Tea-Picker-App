import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/tea_entry.dart';

/// Builds the monthly tea collection report as a branded, print-ready PDF.
///
/// Pure function of its inputs (no Flutter, no network) so it can be unit
/// tested; [ReportService.sharePdf] loads the fonts and logo and shares it.
class PdfReportBuilder {
  // Brand palette taken from the app icon's two leaves.
  static final _forest = PdfColor.fromInt(0xFF0B4D26);
  static final _green = PdfColor.fromInt(0xFF1B6B34);
  static final _leaf = PdfColor.fromInt(0xFF8CC63F);
  static final _lime = PdfColor.fromInt(0xFFA6D92A);
  static final _gold = PdfColor.fromInt(0xFFC8A04A);
  static final _ink = PdfColor.fromInt(0xFF1E2A22);
  static final _muted = PdfColor.fromInt(0xFF6A786F);
  static final _line = PdfColor.fromInt(0xFFDDE5DA);
  static final _tint = PdfColor.fromInt(0xFFF3F7EE);
  static final _amber = PdfColor.fromInt(0xFFB26A00);

  static final NumberFormat _kg = NumberFormat('#,##0.##');
  static final NumberFormat _kg1 = NumberFormat('#,##0.0');
  static final NumberFormat _rs = NumberFormat('#,##0.00');

  final DateTime month;
  final String? pickerName;
  final List<PickerDay> days;
  final String? preparedBy;
  final DateTime generatedAt;
  final pw.ImageProvider? logo;
  final pw.Font? base;
  final pw.Font? bold;
  final pw.Font? display;
  final List<pw.Font> fallback;

  PdfReportBuilder({
    required this.month,
    required this.pickerName,
    required this.days,
    this.preparedBy,
    DateTime? generatedAt,
    this.logo,
    this.base,
    this.bold,
    this.display,
    this.fallback = const [],
  }) : generatedAt = generatedAt ?? DateTime.now();

  String get _monthLabel => DateFormat('MMMM yyyy').format(month);

  pw.TextStyle get _displayStyle => pw.TextStyle(
        font: display ?? pw.Font.timesBold(),
        fontFallback: fallback,
      );

  Future<Uint8List> build() async {
    final summaries = summarisePickers(days);
    final doc = pw.Document(
      title: 'Tea Collection Report – $_monthLabel',
      author: preparedBy ?? 'Tea Picker App',
      creator: 'Tea Picker App',
      subject: pickerName ?? 'All pickers',
    );

    final theme = (base != null
            ? pw.ThemeData.withFont(base: base, bold: bold ?? base, fontFallback: fallback)
            : pw.ThemeData.base())
        .copyWith(defaultTextStyle: pw.TextStyle(fontSize: 9, color: _ink, fontFallback: fallback));

    doc.addPage(pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 0, 36, 24),
        theme: theme,
        buildBackground: _background,
      ),
      header: _header,
      footer: _footer,
      build: (ctx) => [
        _kpis(),
        pw.SizedBox(height: 20),
        if (pickerName == null && summaries.isNotEmpty) ...[
          _sectionTitle('Picker summary', 'Totals for each tea picker this month'),
          _pickerTable(summaries),
          pw.SizedBox(height: 20),
        ],
        _sectionTitle('Daily collection', 'Kilograms of tea leaves picked each day'),
        _dailyChart(),
        pw.SizedBox(height: 20),
        _sectionTitle('Daily details', 'Every picker, every day: the basis of all totals above'),
        _detailTable(),
        if (days.any((d) => d.hasLateEntries))
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Text('† Includes weight that was recorded in the app on a later day.',
                style: pw.TextStyle(fontSize: 7, color: _muted)),
          ),
        pw.SizedBox(height: 22),
        _closing(),
      ],
    ));

    return doc.save();
  }

  // ---------------------------------------------------------------- page chrome

  static const double _bandHeight = 132;

  pw.Widget _background(pw.Context ctx) {
    final first = ctx.pageNumber == 1;
    return pw.FullPage(
      ignoreMargins: true,
      child: pw.Stack(children: [
        // Watermark: the leaf logo, very faint, in the middle of every page.
        if (logo != null)
          pw.Center(
            child: pw.Opacity(
              opacity: 0.07,
              child: pw.Image(logo!, width: 330),
            ),
          ),
        if (first)
          pw.Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: pw.Container(
              height: _bandHeight,
              decoration: pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  begin: pw.Alignment.topLeft,
                  end: pw.Alignment.bottomRight,
                  colors: [_forest, _green],
                ),
              ),
            ),
          ),
        if (first)
          pw.Positioned(
            left: 0,
            right: 0,
            top: _bandHeight,
            child: pw.Row(children: [
              pw.Expanded(flex: 3, child: pw.Container(height: 3, color: _gold)),
              pw.Expanded(flex: 1, child: pw.Container(height: 3, color: _lime)),
            ]),
          )
        else
          pw.Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: pw.Row(children: [
              pw.Expanded(flex: 3, child: pw.Container(height: 5, color: _forest)),
              pw.Expanded(flex: 1, child: pw.Container(height: 5, color: _lime)),
            ]),
          ),
      ]),
    );
  }

  pw.Widget _header(pw.Context ctx) {
    if (ctx.pageNumber == 1) {
      return pw.Container(
        height: _bandHeight + 3,
        margin: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.Container(
                width: 64,
                height: 64,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  shape: pw.BoxShape.circle,
                  border: pw.Border.all(color: _gold, width: 1.5),
                ),
                child: pw.Image(logo!),
              ),
            if (logo != null) pw.SizedBox(width: 16),
            pw.Expanded(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('MONTHLY STATEMENT',
                      style: pw.TextStyle(
                          color: _lime, fontSize: 8, letterSpacing: 2.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text('Tea Collection Report',
                      style: _displayStyle.copyWith(color: PdfColors.white, fontSize: 26)),
                  pw.SizedBox(height: 4),
                  pw.Text(pickerName == null ? 'All tea pickers' : 'Tea picker: $pickerName',
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                ],
              ),
            ),
            pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(DateFormat('MMMM').format(month).toUpperCase(),
                    style: _displayStyle.copyWith(color: PdfColors.white, fontSize: 16, letterSpacing: 1.5)),
                pw.Text(DateFormat('yyyy').format(month),
                    style: pw.TextStyle(color: _gold, fontSize: 22, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ],
        ),
      );
    }
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 22, bottom: 14),
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.8))),
      child: pw.Row(children: [
        if (logo != null) pw.Image(logo!, width: 16, height: 16),
        if (logo != null) pw.SizedBox(width: 6),
        pw.Text('Tea Collection Report', style: _displayStyle.copyWith(color: _forest, fontSize: 11)),
        pw.Spacer(),
        pw.Text('${pickerName ?? 'All tea pickers'}  ·  $_monthLabel',
            style: pw.TextStyle(color: _muted, fontSize: 8)),
      ]),
    );
  }

  pw.Widget _footer(pw.Context ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: _line, width: 0.8))),
        child: pw.Row(children: [
          pw.Text('Tea Picker App', style: pw.TextStyle(color: _green, fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.Text('  ·  Generated ${DateFormat('dd MMM yyyy, h:mm a').format(generatedAt)}',
              style: pw.TextStyle(color: _muted, fontSize: 7)),
          pw.Spacer(),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(color: _muted, fontSize: 7)),
        ]),
      );

  // ---------------------------------------------------------------- sections

  pw.Widget _sectionTitle(String title, String subtitle) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Container(width: 3, height: 22, color: _gold),
          pw.SizedBox(width: 8),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(title, style: _displayStyle.copyWith(color: _forest, fontSize: 14)),
            pw.Text(subtitle, style: pw.TextStyle(color: _muted, fontSize: 7.5)),
          ]),
        ]),
      );

  pw.Widget _kpis() {
    final weight = days.fold(0.0, (s, d) => s + d.weight);
    final pay = days.fold(0.0, (s, d) => s + d.total);
    final workDays = days.map((d) => d.date).toSet().length;
    final entries = days.fold(0, (s, d) => s + d.entries.length);
    final avg = workDays == 0 ? 0.0 : weight / workDays;

    pw.Widget card(String label, String value, String unit, String note, PdfColor accent) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 4),
            padding: const pw.EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: _line, width: 0.8),
            ),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Container(width: 18, height: 2.5, color: accent),
              pw.SizedBox(height: 6),
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(color: _muted, fontSize: 6.5, letterSpacing: 1.2, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.RichText(
                text: pw.TextSpan(children: [
                  if (unit == 'Rs')
                    pw.TextSpan(text: 'Rs ', style: pw.TextStyle(color: _muted, fontSize: 9)),
                  pw.TextSpan(
                      text: value,
                      style: pw.TextStyle(color: _forest, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                  if (unit != 'Rs' && unit.isNotEmpty)
                    pw.TextSpan(text: ' $unit', style: pw.TextStyle(color: _muted, fontSize: 9)),
                ]),
              ),
              pw.SizedBox(height: 2),
              pw.Text(note, style: pw.TextStyle(color: _muted, fontSize: 6.5)),
            ]),
          ),
        );

    return pw.Row(children: [
      card('Tea leaves', _kg1.format(weight), 'kg', '$entries weighings', _leaf),
      card('Total payable', _rs.format(pay), 'Rs', 'wages + bus fees', _gold),
      card('Picking days', '$workDays', 'days', 'in $_monthLabel', _green),
      card('Daily average', _kg1.format(avg), 'kg', 'per picking day', _lime),
    ]);
  }

  pw.Widget _cell(String text,
          {bool right = false, pw.TextStyle? style, pw.EdgeInsets? pad}) =>
      pw.Padding(
        padding: pad ?? const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(text, style: style, textAlign: right ? pw.TextAlign.right : pw.TextAlign.left),
      );

  pw.TableRow _headRow(List<String> labels, int textCols) => pw.TableRow(
        repeat: true,
        decoration: pw.BoxDecoration(color: _forest),
        children: [
          for (var i = 0; i < labels.length; i++)
            _cell(labels[i],
                right: i >= textCols,
                pad: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.4)),
        ],
      );

  pw.TableRow _totalRow(List<String> cells, int textCols) => pw.TableRow(
        decoration: pw.BoxDecoration(
          color: _tint,
          border: pw.Border(top: pw.BorderSide(color: _gold, width: 1.2)),
        ),
        children: [
          for (var i = 0; i < cells.length; i++)
            _cell(cells[i],
                right: i >= textCols,
                pad: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                style: pw.TextStyle(color: _forest, fontWeight: pw.FontWeight.bold)),
        ],
      );

  pw.Widget _pickerTable(List<PickerSummary> summaries) {
    final totalKg = summaries.fold(0.0, (s, p) => s + p.weight);
    final maxKg = summaries.fold(0.0, (m, p) => p.weight > m ? p.weight : m);

    pw.Widget share(double kg) {
      final pct = totalKg == 0 ? 0.0 : kg / totalKg;
      final filled = maxKg == 0 ? 0 : (kg / maxKg * 100).round();
      final radius = pw.BorderRadius.circular(2.5);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Container(
              height: 5,
              decoration: pw.BoxDecoration(color: _line, borderRadius: radius),
              child: pw.Row(children: [
                if (filled > 0)
                  pw.Expanded(
                    flex: filled,
                    child: pw.Container(decoration: pw.BoxDecoration(color: _leaf, borderRadius: radius)),
                  ),
                if (filled < 100) pw.Expanded(flex: 100 - filled, child: pw.SizedBox()),
              ]),
            ),
          ),
          pw.SizedBox(
            width: 26,
            child: pw.Text('${(pct * 100).toStringAsFixed(0)}%',
                textAlign: pw.TextAlign.right, style: pw.TextStyle(color: _muted, fontSize: 7)),
          ),
        ]),
      );
    }

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1.6),
        3: pw.FlexColumnWidth(2.4),
        4: pw.FlexColumnWidth(2),
        5: pw.FlexColumnWidth(1.6),
        6: pw.FlexColumnWidth(2.1),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      border: pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _forest),
          children: [
            for (final (i, h) in ['Picker', 'Days', 'Weight (kg)', 'Share of weight', 'Leaf wages', 'Bus fee', 'Total (Rs)'].indexed)
              _cell(h,
                  right: i != 0 && i != 3,
                  pad: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  style: pw.TextStyle(color: PdfColors.white, fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
          ],
        ),
        for (final (i, p) in summaries.indexed)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isOdd ? _tint : PdfColors.white),
            children: [
              _cell(p.pickerName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              _cell('${p.dayCount}', right: true),
              _cell(_kg.format(p.weight), right: true),
              share(p.weight),
              _cell(_rs.format(p.leafWages), right: true),
              _cell(_rs.format(p.busFee), right: true),
              _cell(_rs.format(p.total), right: true, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        _totalRow([
          'TOTAL',
          '${days.map((d) => d.date).toSet().length}',
          _kg.format(totalKg),
          '',
          _rs.format(summaries.fold(0.0, (s, p) => s + p.leafWages)),
          _rs.format(summaries.fold(0.0, (s, p) => s + p.busFee)),
          _rs.format(summaries.fold(0.0, (s, p) => s + p.total)),
        ], 1),
      ],
    );
  }

  pw.Widget _dailyChart() {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final perDay = List<double>.filled(daysInMonth, 0);
    for (final d in days) {
      final dt = d.pickedOn;
      if (dt.year == month.year && dt.month == month.month) perDay[dt.day - 1] += d.weight;
    }
    final maxKg = perDay.fold(0.0, (m, v) => v > m ? v : m);
    const chartHeight = 90.0;
    var peakDay = 0;
    for (var i = 0; i < perDay.length; i++) {
      if (perDay[i] > perDay[peakDay]) peakDay = i;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: _line, width: 0.8),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          height: chartHeight + 10,
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _muted, width: 0.6))),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < daysInMonth; i++)
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 1.6),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.end,
                      children: [
                        if (perDay[i] > 0 && i == peakDay)
                          pw.Text(_kg.format(perDay[i]),
                              style: pw.TextStyle(fontSize: 5.5, color: _forest, fontWeight: pw.FontWeight.bold)),
                        pw.Container(
                          height: maxKg == 0 ? 0 : (perDay[i] / maxKg * chartHeight).clamp(perDay[i] > 0 ? 1.5 : 0, chartHeight),
                          decoration: pw.BoxDecoration(
                            color: i == peakDay && perDay[i] > 0 ? _gold : _leaf,
                            borderRadius: const pw.BorderRadius.vertical(top: pw.Radius.circular(1.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Row(children: [
          for (var i = 0; i < daysInMonth; i++)
            pw.Expanded(
              child: pw.Text('${i + 1}',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 5.5, color: perDay[i] > 0 ? _ink : _muted)),
            ),
        ]),
        pw.SizedBox(height: 6),
        pw.Row(children: [
          pw.Container(width: 7, height: 7, color: _leaf),
          pw.Text('  kg picked per day', style: pw.TextStyle(fontSize: 6.5, color: _muted)),
          pw.SizedBox(width: 12),
          if (maxKg > 0) ...[
            pw.Container(width: 7, height: 7, color: _gold),
            pw.Text(
                '  Best day: ${DateFormat('EEE d MMM').format(DateTime(month.year, month.month, peakDay + 1))}'
                '  (${_kg.format(maxKg)} kg)',
                style: pw.TextStyle(fontSize: 6.5, color: _muted)),
          ],
        ]),
      ]),
    );
  }

  pw.Widget _detailTable() {
    final rows = <pw.TableRow>[_headRow(['Date', 'Picker', 'Entries', 'Weight (kg)', 'Leaf wages', 'Bus fee', 'Total (Rs)'], 2)];
    String? lastDate;
    var band = false;
    for (final d in days) {
      final newDate = d.date != lastDate;
      if (newDate) band = !band;
      lastDate = d.date;
      rows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: band ? PdfColors.white : _tint,
          border: newDate ? pw.Border(top: pw.BorderSide(color: _line, width: 0.6)) : null,
        ),
        children: [
          _cell(newDate ? DateFormat('EEE dd-MM').format(d.pickedOn) : '',
              style: pw.TextStyle(color: _green, fontWeight: pw.FontWeight.bold)),
          _cell(d.hasLateEntries ? '${d.pickerName} †' : d.pickerName,
              style: d.hasLateEntries ? pw.TextStyle(color: _amber) : null),
          _cell('${d.entries.length}', right: true),
          _cell(_kg.format(d.weight), right: true),
          _cell(_rs.format(d.leafWages), right: true),
          _cell(_rs.format(d.busFee), right: true),
          _cell(_rs.format(d.total), right: true, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ],
      ));
    }
    rows.add(_totalRow([
      'TOTAL',
      '',
      '${days.fold(0, (s, d) => s + d.entries.length)}',
      _kg.format(days.fold(0.0, (s, d) => s + d.weight)),
      _rs.format(days.fold(0.0, (s, d) => s + d.leafWages)),
      _rs.format(days.fold(0.0, (s, d) => s + d.busFee)),
      _rs.format(days.fold(0.0, (s, d) => s + d.total)),
    ], 2));

    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(1.7),
        1: pw.FlexColumnWidth(3),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.7),
        4: pw.FlexColumnWidth(2),
        5: pw.FlexColumnWidth(1.6),
        6: pw.FlexColumnWidth(2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  pw.Widget _closing() {
    final pay = days.fold(0.0, (s, d) => s + d.total);
    final weight = days.fold(0.0, (s, d) => s + d.weight);

    pw.Widget signature(String label, String? name) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(height: 26, child: name == null ? null : pw.Align(
              alignment: pw.Alignment.bottomLeft,
              child: pw.Text(name, style: _displayStyle.copyWith(color: _forest, fontSize: 11)),
            )),
            pw.Container(height: 0.8, color: _muted),
            pw.SizedBox(height: 3),
            pw.Text(label.toUpperCase(), style: pw.TextStyle(color: _muted, fontSize: 6.5, letterSpacing: 1.2)),
          ]),
        );

    return pw.Column(children: [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(colors: [_forest, _green]),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('TOTAL PAYABLE  ·  ${_monthLabel.toUpperCase()}',
                  style: pw.TextStyle(color: _lime, fontSize: 7.5, letterSpacing: 1.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text('for ${_kg.format(weight)} kg of tea leaves',
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)),
            ]),
          ),
          pw.Text('Rs ${_rs.format(pay)}',
              style: _displayStyle.copyWith(color: PdfColors.white, fontSize: 20)),
        ]),
      ),
      pw.SizedBox(height: 26),
      pw.Row(children: [
        signature('Prepared by', preparedBy),
        pw.SizedBox(width: 40),
        signature('Checked by', null),
      ]),
      pw.SizedBox(height: 14),
      pw.Text('All amounts are in Sri Lankan Rupees. Weights are in kilograms. Bus fee is charged once per picker per day.',
          textAlign: pw.TextAlign.center, style: pw.TextStyle(color: _muted, fontSize: 6.5)),
    ]);
  }
}
