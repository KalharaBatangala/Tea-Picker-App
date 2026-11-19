import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tea_picker_app/models/tea_entry.dart';
import 'package:tea_picker_app/services/pdf_report.dart';

/// Sample month: 3 pickers on most days, one entry typed in 4 days late.
List<PickerDay> sampleMonth() {
  final entries = <TeaEntry>[];
  const pickers = ['Kamala', 'Sunil Perera', 'නිමල්'];
  for (var day = 1; day <= 28; day++) {
    if (day % 7 == 0) continue; // Sundays off
    final date = dayKey(DateTime(2026, 11, day));
    for (final (i, p) in pickers.indexed) {
      if ((day + i) % 5 == 0) continue;
      for (var n = 0; n < 2; n++) {
        final kg = 6.0 + ((day * 7 + i * 3 + n * 5) % 11);
        final late = day == 11 && i == 0;
        entries.add(TeaEntry(
          id: '$p-$date-$n',
          pickerName: p,
          weight: kg,
          enteredBy: 'Tester',
          createdAt: late ? DateTime(2026, 11, 15, 19, n) : DateTime.parse('${date}T1$n:30:00'),
          date: date,
          wages: kg * 50,
          rate: 50,
          busFee: 100,
        ));
      }
    }
  }
  return groupByPickerDay(entries);
}

void main() {
  test('recordedLater compares typed-in day with picking day', () {
    final e = TeaEntry(
      id: 'x', pickerName: 'A', weight: 1, enteredBy: 'T', wages: 50,
      createdAt: DateTime(2026, 11, 19, 8), date: '2026-11-17',
    );
    expect(e.recordedLater, isTrue);
    expect(e.pickedOn, DateTime(2026, 11, 17));
    expect(
      TeaEntry(id: 'y', pickerName: 'A', weight: 1, enteredBy: 'T', wages: 50,
              createdAt: DateTime(2026, 11, 17, 23), date: '2026-11-17')
          .recordedLater,
      isFalse,
    );
  });

  test('builds a multi-page report for all pickers and for one picker', () async {
    final days = sampleMonth();
    final logoFile = File('assets/icons/app_icon.png');
    final logo = pw.MemoryImage(logoFile.readAsBytesSync());

    // Optional real fonts for a visual preview: REPORT_FONTS=<dir with the .ttf files>.
    final fontDir = Platform.environment['REPORT_FONTS'];
    pw.Font? font(String name) =>
        fontDir == null ? null : pw.Font.ttf(File('$fontDir/$name.ttf').readAsBytesSync().buffer.asByteData());

    for (final picker in [null, 'Kamala']) {
      final selected = picker == null ? days : days.where((d) => d.pickerName == picker).toList();
      final bytes = await PdfReportBuilder(
        month: DateTime(2026, 11),
        pickerName: picker,
        days: selected,
        preparedBy: 'Kalhara Batangala',
        generatedAt: DateTime(2026, 11, 30, 18, 5),
        logo: logo,
        base: font('NotoSans-Regular'),
        bold: font('NotoSans-Bold'),
        display: font('PlayfairDisplay-Bold'),
        fallback: [?font('NotoSansSinhala-Regular')],
      ).build();

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final out = Platform.environment['REPORT_OUT'];
      if (out != null) File('$out/report_${picker ?? 'all'}.pdf').writeAsBytesSync(bytes);
    }
  });
}
