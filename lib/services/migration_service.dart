import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../firestore_service.dart';
import '../models/tea_entry.dart';

/// A record as stored by the old app (cloud `records` / `historical_records`
/// or the phone's old SQLite tables).
class OldRow {
  final String? uuid;
  final String pickerName;
  final double weight;
  final String enteredBy;
  final String timestamp; // 'dd-MM-yyyy h:mm a'
  final double wages;
  final bool archived; // came from a historical table
  final bool cloudDeleted; // cloud `records` doc flagged deleted

  OldRow({
    required this.uuid,
    required this.pickerName,
    required this.weight,
    required this.enteredBy,
    required this.timestamp,
    required this.wages,
    this.archived = false,
    this.cloudDeleted = false,
  });

  factory OldRow.fromMap(Map<String, dynamic> m,
      {required String? uuid, bool archived = false}) {
    final id = (uuid != null && uuid.trim().isNotEmpty) ? uuid.trim() : null;
    return OldRow(
      uuid: id,
      pickerName: '${m['picker_name'] ?? ''}'.trim(),
      weight: _num(m['weight']),
      enteredBy: '${m['entered_by'] ?? 'Unknown'}'.trim(),
      timestamp: '${m['timestamp'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
      wages: _num(m['wages']),
      archived: archived,
      cloudDeleted: m['deleted'] == true,
    );
  }

  String get signature =>
      '${pickerKey(pickerName)}|$timestamp|${weight.toStringAsFixed(3)}|$enteredBy';

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
}

class MigrationPlan {
  final List<TeaEntry> entries;
  final Set<String> reviewIds; // deleted in the old cloud, origin unclear
  final int skippedUnreadable;
  MigrationPlan(this.entries, this.reviewIds, this.skippedUnreadable);
}

final RegExp _oldTimestamp =
    RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})\s+(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]\.?');

DateTime? parseOldTimestamp(String ts) {
  final m = _oldTimestamp.firstMatch(ts);
  if (m == null) return null;
  int hour = int.parse(m[4]!) % 12;
  if (m[6]!.toLowerCase() == 'p') hour += 12;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!), hour, int.parse(m[5]!));
}

/// Merges every old copy of every record into one clean list.
///
/// * Rows that share a UUID are the same record (the old sync often uploaded
///   the same record more than once).
/// * Old history rows saved before UUIDs existed have no id; they are matched
///   by picker + time + weight + entered-by. If such a row matches a UUID
///   record it is the same record and is dropped; otherwise it gets a
///   deterministic id so every phone running the migration produces the same id.
/// * A record counts as deleted only if the old cloud flagged it deleted and it
///   never reached history (the old app used the same flag for "archived").
MigrationPlan buildMigrationPlan(Iterable<OldRow> rows) {
  final Map<String, List<OldRow>> byUuid = {};
  final Map<String, List<OldRow>> legacyBySig = {};
  int unreadable = 0;

  for (final r in rows) {
    if (r.pickerName.isEmpty || parseOldTimestamp(r.timestamp) == null) {
      unreadable++;
      continue;
    }
    if (r.uuid != null) {
      byUuid.putIfAbsent(r.uuid!, () => []).add(r);
    } else {
      legacyBySig.putIfAbsent(r.signature, () => []).add(r);
    }
  }

  final uuidSignatures = {for (final g in byUuid.values) for (final r in g) r.signature};
  final entries = <TeaEntry>[];
  final review = <String>{};

  TeaEntry toEntry(String id, OldRow r, bool deleted) {
    final created = parseOldTimestamp(r.timestamp)!;
    return TeaEntry(
      id: id,
      pickerName: r.pickerName,
      weight: r.weight,
      enteredBy: r.enteredBy,
      createdAt: created,
      date: dayKey(created),
      wages: r.wages,
      legacy: true,
      deleted: deleted,
    );
  }

  byUuid.forEach((id, group) {
    final archived = group.any((r) => r.archived);
    final cloudDeleted = group.any((r) => r.cloudDeleted);
    final deleted = !archived && cloudDeleted;
    if (deleted) review.add(id);
    final best = group.firstWhere((r) => r.archived, orElse: () => group.first);
    entries.add(toEntry(id, best, deleted));
  });

  legacyBySig.forEach((sig, group) {
    if (uuidSignatures.contains(sig)) return;
    final id = const Uuid().v5(Namespace.url.value, 'tea-picker-legacy:$sig');
    entries.add(toEntry(id, group.first, false));
  });

  entries.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return MigrationPlan(entries, review, unreadable);
}

/// Copies data from the old app's storage into the new collections.
/// Safe to run any number of times: it only ever adds documents that don't
/// exist yet, so it can never undo a delete or overwrite a newer edit.
class MigrationService {
  static const _localDoneKey = 'v2_local_migration_done';
  static final _fs = FirebaseFirestore.instance;
  static bool _running = false;

  /// Returns a short human-readable summary, or null if nothing was done.
  static Future<String?> run({bool force = false}) async {
    if (_running) return null;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final marker = _fs.collection('settings').doc('migration');

      // Needs the server: confirms we're online and reads the shared marker.
      final markerSnap =
          await marker.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
      final cloudDone = markerSnap.data()?['cloud_done'] == true;
      final localDone = prefs.getBool(_localDoneKey) ?? false;
      if (!force && cloudDone && localDone) return null;

      final rows = <OldRow>[];
      final pickerNames = <String>{};
      Map<String, dynamic>? localConfig;

      if (force || !cloudDone) {
        final oldRecords = await _fs.collection('records').get();
        for (final d in oldRecords.docs) {
          rows.add(OldRow.fromMap(d.data(), uuid: d.data()['id'] as String?));
        }
        final oldHistory = await _fs.collection('historical_records').get();
        for (final d in oldHistory.docs) {
          // Docs saved after the duplicate fix use the UUID as doc id and field.
          rows.add(OldRow.fromMap(d.data(), uuid: d.data()['record_id'] as String?, archived: true));
        }
        final oldPickers = await _fs.collection('pickers').get();
        pickerNames.addAll(oldPickers.docs.map((d) => '${d.data()['name'] ?? ''}'.trim()));
      }

      if (force || !localDone) {
        final local = await _readLocalDatabase();
        rows.addAll(local.rows);
        pickerNames.addAll(local.pickers);
        localConfig = local.config;
      }

      final plan = buildMigrationPlan(rows);
      final added = await _addMissing(
        FirestoreService.entries,
        {
          for (final e in plan.entries)
            e.id: {
              ...e.toMap(),
              'migrated': true,
              if (plan.reviewIds.contains(e.id)) 'review': 'deleted_in_old_app',
              'updated_at': FieldValue.serverTimestamp(),
            }
        },
      );

      pickerNames.removeWhere((n) => n.isEmpty);
      final addedPickers = await _addMissing(FirestoreService.pickers, {
        for (final n in pickerNames)
          pickerKey(n): {'name': n, 'active': true, 'updated_at': FieldValue.serverTimestamp()}
      });

      final rates = await FirestoreService.ratesDoc.get(const GetOptions(source: Source.server));
      if (!rates.exists) {
        await FirestoreService.ratesDoc.set({
          'wage_rate': (localConfig?['wage_rate'] as num?)?.toDouble() ?? Rates.defaults.wageRate,
          'bus_fee': (localConfig?['bus_fee'] as num?)?.toDouble() ?? Rates.defaults.busFee,
          'updated_at': FieldValue.serverTimestamp(),
        });
      }

      await marker.set({
        'cloud_done': true,
        'last_run': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await prefs.setBool(_localDoneKey, true);

      if (added == 0 && addedPickers == 0) return force ? 'Old data checked: nothing new to import.' : null;
      return 'Imported $added old entries and $addedPickers pickers.';
    } catch (e) {
      debugPrint('Migration not completed (will retry next launch): $e');
      if (force) return 'Import failed – check your internet connection and try again.';
      return null;
    } finally {
      _running = false;
    }
  }

  /// Writes only the docs whose ids don't exist yet. Returns how many were added.
  static Future<int> _addMissing(
      CollectionReference<Map<String, dynamic>> col, Map<String, Map<String, dynamic>> docs) async {
    final ids = docs.keys.toList();
    final existing = <String>{};
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await col
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server));
      existing.addAll(snap.docs.map((d) => d.id));
    }
    final missing = ids.where((id) => !existing.contains(id)).toList();
    for (var i = 0; i < missing.length; i += 400) {
      final batch = _fs.batch();
      for (final id in missing.skip(i).take(400)) {
        batch.set(col.doc(id), docs[id]!);
      }
      await batch.commit();
    }
    return missing.length;
  }

  static Future<({List<OldRow> rows, Set<String> pickers, Map<String, dynamic>? config})>
      _readLocalDatabase() async {
    final rows = <OldRow>[];
    final pickers = <String>{};
    Map<String, dynamic>? config;
    final path = join(await getDatabasesPath(), 'tea_picker.db');
    if (!await databaseExists(path)) return (rows: rows, pickers: pickers, config: config);

    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    Future<List<Map<String, dynamic>>> read(String table) async {
      try {
        return await db.query(table);
      } catch (_) {
        return const []; // table missing on very old installs
      }
    }

    try {
      for (final r in await read('records')) {
        rows.add(OldRow.fromMap(r, uuid: r['record_id'] as String?));
      }
      for (final r in await read('historical_records')) {
        // Installs from before the duplicate fix have no record_id column.
        rows.add(OldRow.fromMap(r, uuid: r['record_id'] as String?, archived: true));
      }
      pickers.addAll((await read('pickers')).map((p) => '${p['name'] ?? ''}'.trim()));
      final cfg = await read('config');
      if (cfg.isNotEmpty) config = cfg.first;
    } finally {
      await db.close();
    }
    return (rows: rows, pickers: pickers, config: config);
  }
}
