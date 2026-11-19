import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

final DateFormat dayKeyFormat = DateFormat('yyyy-MM-dd');
final DateFormat monthKeyFormat = DateFormat('yyyy-MM');
final DateFormat displayDateFormat = DateFormat('dd-MM-yyyy');
final DateFormat displayTimeFormat = DateFormat('h:mm a');

String dayKey(DateTime d) => dayKeyFormat.format(d);
String monthKey(DateTime d) => monthKeyFormat.format(d);

/// Normalised key used to match a picker regardless of case / extra spaces.
String pickerKey(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ').replaceAll('/', '_');

/// One weighing of tea leaves. Stored in Firestore `entries/{id}`.
///
/// [wages] is the leaf payment only (weight × rate). The bus fee is stored
/// separately on each entry but charged once per picker per day — see
/// [PickerDay]. Entries imported from the old app ([legacy]) keep the wage
/// total they were saved with, which may already include a bus fee.
class TeaEntry {
  final String id;
  final String pickerName;
  final double weight;
  final String enteredBy;
  final DateTime createdAt;
  final String date;
  final double wages;
  final double? rate;
  final double? busFee;
  final bool legacy;
  final bool deleted;

  /// True while this change only exists on this phone (not yet in the cloud).
  final bool pendingUpload;

  const TeaEntry({
    required this.id,
    required this.pickerName,
    required this.weight,
    required this.enteredBy,
    required this.createdAt,
    required this.date,
    required this.wages,
    this.rate,
    this.busFee,
    this.legacy = false,
    this.deleted = false,
    this.pendingUpload = false,
  });

  String get pickerKeyValue => pickerKey(pickerName);

  /// The day the tea was picked (what every total and report is based on).
  /// [createdAt] is only when the entry was typed into the app.
  DateTime get pickedOn => DateTime.parse(date);

  /// True when the entry was typed in on a later day than it was picked.
  bool get recordedLater => dayKey(createdAt).compareTo(date) > 0;

  factory TeaEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final created = DateTime.fromMillisecondsSinceEpoch(_toInt(d['created_at']));
    return TeaEntry(
      id: doc.id,
      pickerName: (d['picker_name'] as String?) ?? 'Unknown',
      weight: _toDouble(d['weight']),
      enteredBy: (d['entered_by'] as String?) ?? 'Unknown',
      createdAt: created,
      date: (d['date'] as String?) ?? dayKey(created),
      wages: _toDouble(d['wages']),
      rate: d['rate'] == null ? null : _toDouble(d['rate']),
      busFee: d['bus_fee'] == null ? null : _toDouble(d['bus_fee']),
      legacy: d['legacy'] == true,
      deleted: d['deleted'] == true,
      pendingUpload: doc.metadata.hasPendingWrites,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'picker_name': pickerName,
        'picker_key': pickerKeyValue,
        'weight': weight,
        'entered_by': enteredBy,
        'created_at': createdAt.millisecondsSinceEpoch,
        'date': date,
        'month': date.substring(0, 7),
        'wages': wages,
        'rate': rate,
        'bus_fee': busFee,
        'legacy': legacy,
        'deleted': deleted,
      };

  static double _toDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
}

/// All entries of one picker on one day, with the day's pay.
class PickerDay {
  final String pickerName;
  final String date;
  final List<TeaEntry> entries; // oldest first

  PickerDay(this.pickerName, this.date, this.entries);

  DateTime get pickedOn => DateTime.parse(date);
  bool get hasLateEntries => entries.any((e) => e.recordedLater);

  double get weight => entries.fold(0.0, (s, e) => s + e.weight);
  double get leafWages => entries.fold(0.0, (s, e) => s + e.wages);

  /// Bus fee charged once per day, taken from the day's first non-legacy entry.
  double get busFee {
    for (final e in entries) {
      if (!e.legacy) return e.busFee ?? 0.0;
    }
    return 0.0;
  }

  double get total => leafWages + busFee;
}

/// Month (or any range) totals for one picker.
class PickerSummary {
  final String pickerName;
  final List<PickerDay> days;

  PickerSummary(this.pickerName, this.days);

  int get dayCount => days.length;
  int get entryCount => days.fold(0, (s, d) => s + d.entries.length);
  double get weight => days.fold(0.0, (s, d) => s + d.weight);
  double get leafWages => days.fold(0.0, (s, d) => s + d.leafWages);
  double get busFee => days.fold(0.0, (s, d) => s + d.busFee);
  double get total => days.fold(0.0, (s, d) => s + d.total);
}

/// Groups non-deleted entries into picker-days, sorted by date then name.
List<PickerDay> groupByPickerDay(Iterable<TeaEntry> entries) {
  final Map<String, List<TeaEntry>> groups = {};
  for (final e in entries) {
    if (e.deleted) continue;
    groups.putIfAbsent('${e.date}|${e.pickerKeyValue}', () => []).add(e);
  }
  final days = groups.values.map((list) {
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return PickerDay(list.first.pickerName, list.first.date, list);
  }).toList();
  days.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : pickerKey(a.pickerName).compareTo(pickerKey(b.pickerName));
  });
  return days;
}

/// Per-picker totals, sorted by picker name.
List<PickerSummary> summarisePickers(List<PickerDay> days) {
  final Map<String, List<PickerDay>> byPicker = {};
  for (final d in days) {
    byPicker.putIfAbsent(pickerKey(d.pickerName), () => []).add(d);
  }
  final list = byPicker.values.map((d) => PickerSummary(d.first.pickerName, d)).toList();
  list.sort((a, b) => pickerKey(a.pickerName).compareTo(pickerKey(b.pickerName)));
  return list;
}
