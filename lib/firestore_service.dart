// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:connectivity_plus/connectivity_plus.dart';
// import '../database/db_helper.dart';
//
// class FirestoreService {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final FirebaseAuth _auth = FirebaseAuth.instance;
//   final DBHelper _db = DBHelper();
//
//   Future<bool> isOnline() async {
//     var connectivityResult = await Connectivity().checkConnectivity();
//     return connectivityResult.contains(ConnectivityResult.mobile) ||
//         connectivityResult.contains(ConnectivityResult.wifi);
//   }
//
//   Future<void> syncData() async {
//     if (await isOnline()) {
//       await syncPickers();
//       await syncRecords();
//     }
//   }
//
//   Future<void> syncPickers() async {
//     String uid = _auth.currentUser?.uid ?? '';
//     // Download from Firestore to local
//     QuerySnapshot cloudPickers = await _firestore
//         .collection('pickers')
//         .where('user_uid', isEqualTo: uid)
//         .get();
//     for (var doc in cloudPickers.docs) {
//       Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
//       int localId = await _db.getPickerId(data['name']);
//       if (localId == -1) {
//         await _db.insertPicker(data['name']);
//       }
//     }
//
//     // Upload from local to Firestore
//     List<Map<String, dynamic>> localPickers = await _db.getPickers();
//     for (var picker in localPickers) {
//       QuerySnapshot existing = await _firestore
//           .collection('pickers')
//           .where('user_uid', isEqualTo: uid)
//           .where('name', isEqualTo: picker['name'])
//           .get();
//       if (existing.docs.isEmpty) {
//         await _firestore.collection('pickers').add({
//           'name': picker['name'],
//           'user_uid': uid,
//         });
//       }
//     }
//   }
//
//   Future<void> syncRecords() async {
//     String uid = _auth.currentUser?.uid ?? '';
//     // Download from Firestore to local
//     QuerySnapshot cloudRecords = await _firestore
//         .collection('records')
//         .where('user_uid', isEqualTo: uid)
//         .get();
//     for (var doc in cloudRecords.docs) {
//       Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
//       List<Map> existing = await _db.db.then((db) => db.query(
//         'records',
//         where: 'timestamp = ? AND picker_name = ?',
//         whereArgs: [data['timestamp'], data['picker_name']],
//       ));
//       if (existing.isEmpty) {
//         await _db.insertRecord(
//           data['picker_name'],
//           data['weight'],
//           data['entered_by'],
//           data['timestamp'],
//           data['wages'],
//         );
//       }
//     }
//
//     // Upload from local to Firestore
//     List<Map<String, dynamic>> localRecords =
//     await _db.db.then((db) => db.query('records'));
//     for (var record in localRecords) {
//       QuerySnapshot existing = await _firestore
//           .collection('records')
//           .where('user_uid', isEqualTo: uid)
//           .where('timestamp', isEqualTo: record['timestamp'])
//           .where('picker_name', isEqualTo: record['picker_name'])
//           .get();
//       if (existing.docs.isEmpty) {
//         await _firestore.collection('records').add({
//           'picker_name': record['picker_name'],
//           'weight': record['weight'],
//           'entered_by': record['entered_by'],
//           'timestamp': record['timestamp'],
//           'wages': record['wages'],
//           'user_uid': uid,
//         });
//       }
//     }
//   }
//
//   Future<void> uploadRecord(Map<String, dynamic> record) async {
//     if (await isOnline()) {
//       try {
//         await _firestore.collection('records').add(record);
//       } catch (e) {
//         print('Firestore Upload Error: $e');
//       }
//     }
//   }
// }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/db_helper.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DBHelper _db = DBHelper();

  Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);
  }

  Future<void> syncData() async {
    if (await isOnline()) {
      await syncPickers();
      await syncRecords();
    }
  }

  Future<void> syncPickers() async {
    String uid = _auth.currentUser?.uid ?? '';
    // Download from Firestore to local
    QuerySnapshot cloudPickers = await _firestore
        .collection('pickers')
        .where('user_uid', isEqualTo: uid)
        .get();
    for (var doc in cloudPickers.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      int localId = await _db.getPickerId(data['name']);
      if (localId == -1) {
        await _db.insertPicker(data['name']);
      }
    }

    // Upload from local to Firestore
    List<Map<String, dynamic>> localPickers = await _db.getPickers();
    for (var picker in localPickers) {
      QuerySnapshot existing = await _firestore
          .collection('pickers')
          .where('user_uid', isEqualTo: uid)
          .where('name', isEqualTo: picker['name'])
          .get();
      if (existing.docs.isEmpty) {
        await _firestore.collection('pickers').add({
          'name': picker['name'],
          'user_uid': uid,
        });
      }
    }
  }

  Future<void> syncRecords() async {
    String uid = _auth.currentUser?.uid ?? '';
    // Download from Firestore to local
    QuerySnapshot cloudRecords = await _firestore
        .collection('records')
        .where('user_uid', isEqualTo: uid)
        .get();
    for (var doc in cloudRecords.docs) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      List<Map> existing = await _db.db.then((db) => db.query(
        'records',
        where: 'timestamp = ? AND picker_name = ?',
        whereArgs: [data['timestamp'], data['picker_name']],
      ));
      if (existing.isEmpty) {
        await _db.insertRecord(
          data['picker_name'],
          data['weight'],
          data['entered_by'],
          data['timestamp'],
          data['wages'],
        );
      }
    }

    // Upload from local to Firestore
    List<Map<String, dynamic>> localRecords =
    await _db.db.then((db) => db.query('records'));
    for (var record in localRecords) {
      QuerySnapshot existing = await _firestore
          .collection('records')
          .where('user_uid', isEqualTo: uid)
          .where('timestamp', isEqualTo: record['timestamp'])
          .where('picker_name', isEqualTo: record['picker_name'])
          .get();
      if (existing.docs.isEmpty) {
        await _firestore.collection('records').add({
          'picker_name': record['picker_name'],
          'weight': record['weight'],
          'entered_by': record['entered_by'],
          'timestamp': record['timestamp'],
          'wages': record['wages'],
          'user_uid': uid,
        });
      }
    }
  }

  Future<void> uploadRecord(Map<String, dynamic> record) async {
    if (await isOnline()) {
      try {
        await _firestore.collection('records').add(record);
      } catch (e) {
        print('Firestore Upload Error: $e');
      }
    }
  }

  Future<void> addPicker(String name) async {
    if (await isOnline()) {
      try {
        await _firestore.collection('pickers').add({
          'name': name,
          'user_uid': _auth.currentUser?.uid,
        });
      } catch (e) {
        print('Firestore Picker Add Error: $e');
      }
    }
  }

  Future<void> deletePicker(String name) async {
    if (await isOnline()) {
      try {
        QuerySnapshot snapshot = await _firestore
            .collection('pickers')
            .where('name', isEqualTo: name)
            .where('user_uid', isEqualTo: _auth.currentUser?.uid)
            .get();
        for (var doc in snapshot.docs) {
          await doc.reference.delete();
        }
      } catch (e) {
        print('Firestore Picker Delete Error: $e');
      }
    }
  }
}