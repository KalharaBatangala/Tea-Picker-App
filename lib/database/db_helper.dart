//
//
// import 'package:sqflite/sqflite.dart';
// import 'package:path/path.dart';
//
// class DBHelper {
//   static Database? _db;
//   static const String dbName = 'tea_picker.db';
//   static const int dbVersion = 1;
//
//   Future<Database> get db async {
//     if (_db != null) return _db!;
//     _db = await initDb();
//     return _db!;
//   }
//
//   Future<Database> initDb() async {
//     String path = join(await getDatabasesPath(), dbName);
//     return await openDatabase(path, version: dbVersion, onCreate: _onCreate);
//   }
//
//   Future _onCreate(Database db, int version) async {
//     await db.execute('''
//       CREATE TABLE pickers (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         name TEXT NOT NULL UNIQUE
//       )
//     ''');
//     await db.execute('''
//       CREATE TABLE records (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         picker_name TEXT NOT NULL,
//         weight REAL NOT NULL,
//         entered_by TEXT NOT NULL,
//         timestamp TEXT NOT NULL,
//         wages REAL NOT NULL
//       )
//     ''');
//     await db.execute('''
//       CREATE TABLE historical_records (
//         id INTEGER PRIMARY KEY AUTOINCREMENT,
//         picker_name TEXT NOT NULL,
//         weight REAL NOT NULL,
//         entered_by TEXT NOT NULL,
//         timestamp TEXT NOT NULL,
//         wages REAL NOT NULL
//       )
//     ''');
//     await db.execute('''
//       CREATE TABLE config (
//         id INTEGER PRIMARY KEY,
//         wage_rate REAL DEFAULT 40.0
//       )
//     ''');
//     await db.insert('config', {'id': 1, 'wage_rate': 40.0});
//   }
//
//   // Picker methods
//   Future<int> insertPicker(String name) async {
//     Database dbClient = await db;
//     return await dbClient.insert('pickers', {'name': name},
//         conflictAlgorithm: ConflictAlgorithm.ignore);
//   }
//
//   Future<List<Map<String, dynamic>>> getPickers() async {
//     Database dbClient = await db;
//     return await dbClient.query('pickers');
//   }
//
//   Future<int> getPickerId(String name) async {
//     Database dbClient = await db;
//     List<Map> pickers =
//     await dbClient.query('pickers', where: 'name = ?', whereArgs: [name]);
//     return pickers.isNotEmpty ? pickers[0]['id'] : -1;
//   }
//
//   Future<void> deletePicker(int id) async {
//     Database dbClient = await db;
//     await dbClient.delete('pickers', where: 'id = ?', whereArgs: [id]);
//   }
//
//   // Record methods (temporary, day-to-day)
//   Future<int> insertRecord(String pickerName, double weight, String enteredBy,
//       String timestamp, double wages) async {
//     Database dbClient = await db;
//     return await dbClient.insert('records', {
//       'picker_name': pickerName,
//       'weight': weight,
//       'entered_by': enteredBy,
//       'timestamp': timestamp,
//       'wages': wages,
//     });
//   }
//
//   Future<List<Map<String, dynamic>>> getRecordsForPicker(
//       String pickerName) async {
//     Database dbClient = await db;
//     return await dbClient.query('records',
//         where: 'picker_name = ?', whereArgs: [pickerName], orderBy: 'timestamp DESC');
//   }
//
//   Future<List<Map<String, dynamic>>> getAllPickersWithRecords() async {
//     Database dbClient = await db;
//     return await dbClient.rawQuery('SELECT DISTINCT picker_name FROM records');
//   }
//
//   // Historical methods (permanent)
//   Future<int> insertHistoricalRecord(String pickerName, double weight, String enteredBy,
//       String timestamp, double wages) async {
//     Database dbClient = await db;
//     return await dbClient.insert('historical_records', {
//       'picker_name': pickerName,
//       'weight': weight,
//       'entered_by': enteredBy,
//       'timestamp': timestamp,
//       'wages': wages,
//     });
//   }
//
//   Future<List<Map<String, dynamic>>> getHistoricalRecordsForPicker(
//       String pickerName) async {
//     Database dbClient = await db;
//     return await dbClient.query('historical_records',
//         where: 'picker_name = ?', whereArgs: [pickerName], orderBy: 'timestamp DESC');
//   }
//
//   Future<List<Map<String, dynamic>>> getAllHistoricalPickers() async {
//     Database dbClient = await db;
//     return await dbClient.rawQuery('SELECT DISTINCT picker_name FROM historical_records');
//   }
//
//   Future<void> deleteHistoricalRecord(int id) async {
//     Database dbClient = await db;
//     await dbClient.delete('historical_records', where: 'id = ?', whereArgs: [id]);
//   }
//
//   // Archive and Clear
//   Future<void> archiveRecords() async {
//     Database dbClient = await db;
//     List<Map<String, dynamic>> records = await dbClient.query('records');
//     for (var record in records) {
//       await insertHistoricalRecord(
//         record['picker_name'],
//         record['weight'],
//         record['entered_by'],
//         record['timestamp'],
//         record['wages'],
//       );
//     }
//     await dbClient.delete('records');
//   }
//
//   // Config methods
//   Future<double> getWageRate() async {
//     Database dbClient = await db;
//     List<Map> result = await dbClient.query('config', where: 'id = ?', whereArgs: [1]);
//     return result.isNotEmpty ? result[0]['wage_rate'] : 40.0;
//   }
// }

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;
  static const String dbName = 'tea_picker.db';
  static const int dbVersion = 1;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  Future<Database> initDb() async {
    String path = join(await getDatabasesPath(), dbName);
    return await openDatabase(path, version: dbVersion, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE pickers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        picker_name TEXT NOT NULL,
        weight REAL NOT NULL,
        entered_by TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        wages REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE historical_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        picker_name TEXT NOT NULL,
        weight REAL NOT NULL,
        entered_by TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        wages REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE config (
        id INTEGER PRIMARY KEY,
        wage_rate REAL DEFAULT 40.0
      )
    ''');
    await db.insert('config', {'id': 1, 'wage_rate': 40.0});
  }

  // Picker methods
  Future<int> insertPicker(String name) async {
    Database dbClient = await db;
    return await dbClient.insert('pickers', {'name': name},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> getPickers() async {
    Database dbClient = await db;
    return await dbClient.query('pickers');
  }

  Future<int> getPickerId(String name) async {
    Database dbClient = await db;
    List<Map> pickers =
    await dbClient.query('pickers', where: 'name = ?', whereArgs: [name]);
    return pickers.isNotEmpty ? pickers[0]['id'] : -1;
  }

  Future<void> deletePicker(int id) async {
    Database dbClient = await db;
    await dbClient.delete('pickers', where: 'id = ?', whereArgs: [id]);
  }

  // Record methods (temporary)
  Future<int> insertRecord(String pickerName, double weight, String enteredBy,
      String timestamp, double wages) async {
    Database dbClient = await db;
    return await dbClient.insert('records', {
      'picker_name': pickerName,
      'weight': weight,
      'entered_by': enteredBy,
      'timestamp': timestamp,
      'wages': wages,
    });
  }

  Future<List<Map<String, dynamic>>> getRecordsForPicker(
      String pickerName) async {
    Database dbClient = await db;
    return await dbClient.query('records',
        where: 'picker_name = ?', whereArgs: [pickerName], orderBy: 'timestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getAllPickersWithRecords() async {
    Database dbClient = await db;
    return await dbClient.rawQuery('SELECT DISTINCT picker_name FROM records');
  }

  Future<void> deleteRecord(int id) async {
    Database dbClient = await db;
    await dbClient.delete('records', where: 'id = ?', whereArgs: [id]);
  }

  // Historical methods (permanent)
  Future<int> insertHistoricalRecord(String pickerName, double weight, String enteredBy,
      String timestamp, double wages) async {
    Database dbClient = await db;
    return await dbClient.insert('historical_records', {
      'picker_name': pickerName,
      'weight': weight,
      'entered_by': enteredBy,
      'timestamp': timestamp,
      'wages': wages,
    });
  }

  Future<List<Map<String, dynamic>>> getHistoricalRecordsForPicker(
      String pickerName) async {
    Database dbClient = await db;
    return await dbClient.query('historical_records',
        where: 'picker_name = ?', whereArgs: [pickerName], orderBy: 'timestamp DESC');
  }

  Future<List<Map<String, dynamic>>> getAllHistoricalPickers() async {
    Database dbClient = await db;
    return await dbClient.rawQuery('SELECT DISTINCT picker_name FROM historical_records');
  }

  Future<void> deleteHistoricalRecord(int id) async {
    Database dbClient = await db;
    await dbClient.delete('historical_records', where: 'id = ?', whereArgs: [id]);
  }

  // Archive and Clear
  Future<void> archiveRecords() async {
    Database dbClient = await db;
    List<Map<String, dynamic>> records = await dbClient.query('records');
    for (var record in records) {
      await insertHistoricalRecord(
        record['picker_name'],
        record['weight'],
        record['entered_by'],
        record['timestamp'],
        record['wages'],
      );
    }
    await dbClient.delete('records');
  }

  // Config methods
  Future<double> getWageRate() async {
    Database dbClient = await db;
    List<Map> result = await dbClient.query('config', where: 'id = ?', whereArgs: [1]);
    return result.isNotEmpty ? result[0]['wage_rate'] : 40.0;
  }
}