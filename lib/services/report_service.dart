import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../firestore_service.dart';
import '../models/tea_entry.dart';
import 'notification_service.dart';
import 'pdf_report.dart';

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
  /// "Date" is the day the tea was picked; "Recorded at" is when it was typed in.
  Future<void> shareCsv({
    required String month,
    required String? pickerName,
    required List<PickerDay> days,
  }) async {
    String esc(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final recorded = DateFormat('dd-MM-yyyy h:mm a');
    final b = StringBuffer()
      ..writeln(['Date', 'Picker', 'Weight (kg)', 'Rate (Rs/kg)', 'Leaf wages (Rs)', 'Bus fee (Rs)',
              'Total (Rs)', 'Entered by', 'Recorded at', 'Recorded later', 'Entry ID']
          .join(','));
    for (final day in days) {
      for (var i = 0; i < day.entries.length; i++) {
        final e = day.entries[i];
        final bus = i == 0 ? day.busFee : 0.0;
        b.writeln([
          displayDateFormat.format(e.pickedOn),
          e.pickerName,
          e.weight.toStringAsFixed(2),
          e.rate?.toStringAsFixed(2) ?? '',
          e.wages.toStringAsFixed(2),
          bus.toStringAsFixed(2),
          (e.wages + bus).toStringAsFixed(2),
          e.enteredBy,
          recorded.format(e.createdAt),
          e.recordedLater ? 'Yes' : 'No',
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

  /// Loads a Google font (cached on the phone after the first download).
  /// Returns null when it can't be fetched, so the PDF uses built-in fonts.
  static Future<pw.Font?> _font(Future<pw.Font> Function() load) async {
    try {
      return await load();
    } catch (e) {
      debugPrint('PDF font not available: $e');
      return null;
    }
  }

  Future<void> sharePdf({
    required DateTime month,
    required String? pickerName,
    required List<PickerDay> days,
  }) async {
    pw.ImageProvider? logo;
    try {
      logo = pw.MemoryImage((await rootBundle.load('assets/icons/app_icon.png')).buffer.asUint8List());
    } catch (e) {
      debugPrint('PDF logo not loaded: $e');
    }

    // Noto fonts render Sinhala/Tamil names; Playfair gives the report its titles.
    final fonts = await Future.wait([
      _font(PdfGoogleFonts.notoSansRegular),
      _font(PdfGoogleFonts.notoSansBold),
      _font(PdfGoogleFonts.playfairDisplayBold),
      _font(PdfGoogleFonts.notoSansSinhalaRegular),
    ]);

    final bytes = await PdfReportBuilder(
      month: month,
      pickerName: pickerName,
      days: days,
      preparedBy: FirebaseAuth.instance.currentUser?.displayName,
      logo: logo,
      base: fonts[0],
      bold: fonts[1],
      display: fonts[2],
      fallback: [?fonts[3]],
    ).build();

    await Printing.sharePdf(bytes: bytes, filename: '${_fileBase(monthKey(month), pickerName)}.pdf');
  }
}
