import 'package:flutter_test/flutter_test.dart';

import 'package:tea_picker_app/models/tea_entry.dart';
import 'package:tea_picker_app/services/migration_service.dart';

TeaEntry entry(String picker, String date, double kg,
        {int minute = 0, double rate = 50, double? bus = 100, bool legacy = false, bool deleted = false}) =>
    TeaEntry(
      id: '$picker-$date-$minute',
      pickerName: picker,
      weight: kg,
      enteredBy: 'Tester',
      createdAt: DateTime.parse('${date}T08:${minute.toString().padLeft(2, '0')}:00'),
      date: date,
      wages: legacy ? kg * rate + (bus ?? 0) : kg * rate,
      rate: legacy ? null : rate,
      busFee: legacy ? null : bus,
      legacy: legacy,
      deleted: deleted,
    );

OldRow old(String? uuid, String picker, String ts, double kg,
        {bool archived = false, bool deleted = false}) =>
    OldRow.fromMap({
      'picker_name': picker,
      'weight': kg,
      'entered_by': 'Amma',
      'timestamp': ts,
      'wages': kg * 50,
      'deleted': deleted,
    }, uuid: uuid, archived: archived);

void main() {
  group('pay rules', () {
    test('bus fee is charged once per picker per day', () {
      final days = groupByPickerDay([
        entry('Kamala', '2026-10-01', 10, minute: 1),
        entry('Kamala', '2026-10-01', 5, minute: 2),
        entry('kamala ', '2026-10-01', 2, minute: 3), // same picker, different spelling
        entry('Kamala', '2026-10-02', 8),
        entry('Sita', '2026-10-01', 4),
      ]);
      expect(days.length, 3);
      final k1 = days.firstWhere((d) => d.pickerName == 'Kamala' && d.date == '2026-10-01');
      expect(k1.weight, 17);
      expect(k1.busFee, 100);
      expect(k1.total, 17 * 50 + 100);

      final summary = summarisePickers(days).firstWhere((s) => s.pickerName == 'Kamala');
      expect(summary.dayCount, 2);
      expect(summary.weight, 25);
      expect(summary.total, 25 * 50 + 200);
    });

    test('deleted entries are excluded and legacy wages are kept as saved', () {
      final days = groupByPickerDay([
        entry('Sita', '2026-10-01', 10, legacy: true),
        entry('Sita', '2026-10-01', 99, minute: 5, deleted: true),
      ]);
      expect(days.single.weight, 10);
      expect(days.single.busFee, 0);
      expect(days.single.total, 10 * 50 + 100);
    });
  });

  group('migration plan', () {
    test('parses old timestamps', () {
      expect(parseOldTimestamp('05-10-2025 9:07 PM'), DateTime(2025, 10, 5, 21, 7));
      expect(parseOldTimestamp('05-10-2025 12:30 AM'), DateTime(2025, 10, 5, 0, 30));
      expect(parseOldTimestamp('garbage'), isNull);
    });

    test('merges duplicate uploads and legacy copies of the same record', () {
      final plan = buildMigrationPlan([
        old('u1', 'Kamala', '05-10-2025 9:07 AM', 10), // cloud records, archived later
        old('u1', 'Kamala', '05-10-2025 9:07 AM', 10), // duplicate upload (race)
        old('u1', 'Kamala', '05-10-2025 9:07 AM', 10, archived: true),
        old(null, 'Kamala', '05-10-2025 9:07 AM', 10, archived: true), // pre-UUID copy
        old(null, 'Sita', '04-10-2025 8:00 AM', 6, archived: true), // only legacy copy
        old(null, 'Sita', '04-10-2025 8:00 AM', 6, archived: true), // uploaded by 2 phones
      ]);
      expect(plan.entries.length, 2);
      expect(plan.entries.where((e) => e.deleted), isEmpty);
      expect(plan.entries.map((e) => e.pickerName), containsAll(['Kamala', 'Sita']));
    });

    test('legacy ids are the same on every phone', () {
      final a = buildMigrationPlan([old(null, 'Sita', '04-10-2025 8:00 AM', 6, archived: true)]);
      final b = buildMigrationPlan([old(null, 'Sita', '04-10-2025 8:00 AM', 6, archived: true)]);
      expect(a.entries.single.id, b.entries.single.id);
    });

    test('archived records are kept; records deleted before archiving are not', () {
      final plan = buildMigrationPlan([
        old('kept', 'A', '01-10-2025 7:00 AM', 3, deleted: true), // flagged by archive...
        old('kept', 'A', '01-10-2025 7:00 AM', 3, archived: true), // ...and in history
        old('gone', 'A', '01-10-2025 7:05 AM', 4, deleted: true), // user deleted on Home
        old('live', 'A', '01-10-2025 7:10 AM', 5), // never archived
      ]);
      final byId = {for (final e in plan.entries) e.id: e};
      expect(byId['kept']!.deleted, isFalse);
      expect(byId['live']!.deleted, isFalse);
      expect(byId['gone']!.deleted, isTrue);
      expect(plan.reviewIds, {'gone'});
    });
  });
}
