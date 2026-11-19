import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'models/tea_entry.dart';

class Picker {
  final String id;
  final String name;
  final bool active;
  const Picker(this.id, this.name, this.active);
}

class Rates {
  final double wageRate;
  final double busFee;

  /// False until the shared rates have been loaded at least once (a new phone
  /// that is offline only knows the defaults).
  final bool known;
  const Rates(this.wageRate, this.busFee, {this.known = true});
  static const defaults = Rates(50.0, 100.0, known: false);
}

/// Single source of truth for all shared data.
///
/// Firestore keeps an offline copy on every phone: reads come from that copy
/// instantly, writes are applied locally first and uploaded automatically when
/// the phone is back online. Every document has a fixed id (UUID for entries,
/// normalised name for pickers), so retrying or re-uploading a write can never
/// create a duplicate. Writes are intentionally NOT awaited – an awaited write
/// only completes once the server confirms it, which freezes the UI offline.
class FirestoreService {
  static final FirebaseFirestore _fs = FirebaseFirestore.instance;

  /// Last cloud error (e.g. permission denied) so the UI can show it.
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  static CollectionReference<Map<String, dynamic>> get entries => _fs.collection('entries');
  static CollectionReference<Map<String, dynamic>> get pickers => _fs.collection('tea_pickers');
  static DocumentReference<Map<String, dynamic>> get ratesDoc =>
      _fs.collection('settings').doc('rates');

  static void configure() {
    _fs.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  static void _report(Object e) {
    debugPrint('Firestore error: $e');
    lastError.value = e is FirebaseException ? '${e.code}: ${e.message}' : '$e';
  }

  static List<TeaEntry> _toEntries(QuerySnapshot<Map<String, dynamic>> snap) => snap.docs
      .map(TeaEntry.fromDoc)
      .where((e) => !e.deleted)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  // ---------- Entries ----------

  Stream<List<TeaEntry>> entriesForDay(String day) => entries
      .where('date', isEqualTo: day)
      .snapshots(includeMetadataChanges: true)
      .map(_toEntries);

  Stream<List<TeaEntry>> entriesForMonth(String month) => entries
      .where('month', isEqualTo: month)
      .snapshots(includeMetadataChanges: true)
      .map(_toEntries);

  Future<List<TeaEntry>> getEntriesForMonth(String month, {bool cacheOnly = false}) async {
    final query = entries.where('month', isEqualTo: month);
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await query
          .get(GetOptions(source: cacheOnly ? Source.cache : Source.serverAndCache))
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      snap = await query.get(const GetOptions(source: Source.cache));
    }
    return _toEntries(snap);
  }

  /// Pull-to-refresh: ask the server for fresh data (the live listeners pick it
  /// up). Fails quietly when offline.
  Future<void> refreshFromServer(Query<Map<String, dynamic>> query) async {
    try {
      await query.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 15));
      lastError.value = null;
    } catch (e) {
      debugPrint('Refresh skipped: $e');
    }
  }

  void addEntry(TeaEntry entry) {
    entries.doc(entry.id).set({
      ...entry.toMap(),
      'updated_at': FieldValue.serverTimestamp(),
    }).catchError(_report);
  }

  void deleteEntry(String id, {String? deletedBy}) {
    entries.doc(id).set({
      'deleted': true,
      'deleted_by': deletedBy,
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError(_report);
  }

  // ---------- Pickers ----------

  Stream<List<Picker>> pickerList({bool activeOnly = true}) =>
      pickers.snapshots().map((snap) {
        final list = snap.docs
            .map((d) => Picker(d.id, (d.data()['name'] as String?) ?? d.id, d.data()['active'] != false))
            .where((p) => !activeOnly || p.active)
            .toList();
        list.sort((a, b) => a.id.compareTo(b.id));
        return list;
      });

  void addPicker(String name) {
    pickers.doc(pickerKey(name)).set({
      'name': name.trim(),
      'active': true,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError(_report);
  }

  /// Soft delete so the picker can't be resurrected by another phone.
  void deletePicker(String id) {
    pickers.doc(id).set({
      'active': false,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError(_report);
  }

  // ---------- Rates (shared by every phone) ----------

  Stream<Rates> rates() => ratesDoc.snapshots().map((d) {
        final data = d.data();
        if (data == null) {
          // Missing on the server = never set, so the defaults really apply.
          return d.metadata.isFromCache ? Rates.defaults : const Rates(50.0, 100.0);
        }
        return Rates(
          (data['wage_rate'] as num?)?.toDouble() ?? Rates.defaults.wageRate,
          (data['bus_fee'] as num?)?.toDouble() ?? Rates.defaults.busFee,
        );
      });

  void saveWageRate(double value) => ratesDoc.set(
      {'wage_rate': value, 'updated_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true)).catchError(_report);

  void saveBusFee(double value) => ratesDoc.set(
      {'bus_fee': value, 'updated_at': FieldValue.serverTimestamp()},
      SetOptions(merge: true)).catchError(_report);
}
