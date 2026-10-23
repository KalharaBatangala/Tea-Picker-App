import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../firestore_service.dart';
import '../models/tea_entry.dart';
import 'notification_service.dart';

final NumberFormat _kg = NumberFormat('#,##0.##');
final NumberFormat _rs = NumberFormat('#,##0.00');

class ReportService {
  final FirestoreService _firestore = FirestoreService();

  /// Re-schedules the 6 PM notification with this month's totals so far.
  Future<void> refreshDailySummaryNotification({bool cacheOnly = false}) async {
    try {
      final entries = await _firestore.getEntriesForMonth(monthKey(DateTime.now()), cacheOnly: cacheOnly);
      final days = groupByPickerDay(entries);
      final weight = days.fold(0.0, (s, d) => s + d.weight);
      final pay = days.fold(0.0, (s, d) => s + d.total);
      await NotificationService.scheduleDailyAtTimeIfNotScheduled(
        id: 200,
        title: '🌿 Tea Leaves Summary',
        body: 'Weight: ${weight.toStringAsFixed(2)} kg\nCost: Rs. ${pay.toStringAsFixed(2)}',
        hour: 18,
        minute: 0,
      );
    } catch (e) {
      debugPrint('Summary notification not updated: $e');
    }
  }

  static String _fileBase(String month, String? picker) {
    final who = picker == null ? 'all' : picker.replaceAll(RegExp(r'[^\w]+'), '_');
    return 'tea_report_${month}_$who';
  }

  /// One row per entry. The day's bus fee is shown on the picker's first entry
  /// of that day, so summing the Total column gives the exact amount payable.
  Future<void> shareCsv({
    required String month,
    required String? pickerName,
    required List<PickerDay> days,
  }) async {
    String esc(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final b = StringBuffer()
      ..writeln(['Date', 'Time', 'Picker', 'Weight (kg)', 'Rate (Rs/kg)', 'Leaf wages (Rs)',
              'Bus fee (Rs)', 'Total (Rs)', 'Entered by', 'Entry ID']
          .join(','));
    for (final day in days) {
      for (var i = 0; i < day.entries.length; i++) {
        final e = day.entries[i];
        final bus = i == 0 ? day.busFee : 0.0;
        b.writeln([
          displayDateFormat.format(e.createdAt),
          displayTimeFormat.format(e.createdAt),
          e.pickerName,
          e.weight.toStringAsFixed(2),
          e.rate?.toStringAsFixed(2) ?? '',
          e.wages.toStringAsFixed(2),
          bus.toStringAsFixed(2),
          (e.wages + bus).toStringAsFixed(2),
          e.enteredBy,
          e.id,
        ].map(esc).join(','));
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_fileBase(month, pickerName)}.csv');
    // BOM so Excel opens Sinhala/Tamil names correctly.
    await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(b.toString())]);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Tea report $month',
    ));
  }

  Future<void> sharePdf({
    required String month,
    required String monthLabel,
    required String? pickerName,
    required List<PickerDay> days,
  }) async {
    pw.ThemeData theme;
    try {
      // Google fonts support Sinhala/Tamil names; cached after first download.
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        fontFallback: [await PdfGoogleFonts.notoSansSinhalaRegular()],
      ).copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 9));
    } catch (_) {
      theme = pw.ThemeData.base().copyWith(defaultTextStyle: const pw.TextStyle(fontSize: 9));
    }

    final summaries = summarisePickers(days);
    final totalKg = summaries.fold(0.0, (s, p) => s + p.weight);
    final totalPay = summaries.fold(0.0, (s, p) => s + p.total);
    final green = PdfColor.fromInt(0xFF2E7D32);
    final headerStyle = pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold);

    pw.Widget table(List<String> headers, List<List<String>> rows,
            {List<String>? footer, int textCols = 1}) =>
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: [...rows, if (footer != null) footer],
          headerStyle: headerStyle,
          headerDecoration: pw.BoxDecoration(color: green),
          cellAlignments: {for (var i = textCols; i < headers.length; i++) i: pw.Alignment.centerRight},
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        );

    final doc = pw.Document(theme: theme);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Tea Picker Report – $monthLabel',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: green)),
        pw.Text('${pickerName ?? 'All pickers'}  •  Generated ${DateFormat('dd-MM-yyyy h:mm a').format(DateTime.now())}'),
        pw.SizedBox(height: 8),
      ]),
      footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}')),
      build: (ctx) => [
        pw.Text('Total weight: ${_kg.format(totalKg)} kg     Total payable: Rs. ${_rs.format(totalPay)}',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('Summary by picker', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        table(
          ['Picker', 'Days', 'Weight (kg)', 'Leaf wages', 'Bus fee', 'Total (Rs)'],
          [
            for (final p in summaries)
              [p.pickerName, '${p.dayCount}', _kg.format(p.weight), _rs.format(p.leafWages),
                _rs.format(p.busFee), _rs.format(p.total)]
          ],
          footer: ['TOTAL', '', _kg.format(totalKg),
            _rs.format(summaries.fold(0.0, (s, p) => s + p.leafWages)),
            _rs.format(summaries.fold(0.0, (s, p) => s + p.busFee)), _rs.format(totalPay)],
        ),
        pw.SizedBox(height: 14),
        pw.Text('Daily details', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        table(
          ['Date', 'Picker', 'Entries', 'Weight (kg)', 'Leaf wages', 'Bus fee', 'Total (Rs)'],
          [
            for (final d in days)
              [displayDateFormat.format(d.entries.first.createdAt), d.pickerName, '${d.entries.length}',
                _kg.format(d.weight), _rs.format(d.leafWages), _rs.format(d.busFee), _rs.format(d.total)]
          ],
          textCols: 2,
        ),
      ],
    ));

    await Printing.sharePdf(bytes: await doc.save(), filename: '${_fileBase(month, pickerName)}.pdf');
  }
}
