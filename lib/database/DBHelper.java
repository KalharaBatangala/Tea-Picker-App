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
        name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        picker_id INTEGER,
        date TEXT NOT NULL,
        kg REAL NOT NULL,
        wages REAL NOT NULL,
        FOREIGN KEY (picker_id) REFERENCES pickers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE config (
        id INTEGER PRIMARY KEY,
        wage_rate REAL DEFAULT 0.0
      )
    ''');
    await db.insert('config', {'id': 1, 'wage_rate': 5.0}); // Default $5/kg
  }

  // CRUD for pickers
  Future<int> insertPicker(String name) async {
    Database dbClient = await db;
    return await dbClient.insert('pickers', {'name': name});
  }

  Future<List<Map>> getPickers() async {
    Database dbClient = await db;
    return await dbClient.query('pickers');
  }

  // CRUD for records
  Future<int> insertRecord(int pickerId, String date, double kg, double wages) async {
    Database dbClient = await db;
    return await dbClient.insert('records', {
      'picker_id': pickerId,
      'date': date,
      'kg': kg,
      'wages': wages,
    });
  }

  Future<List<Map>> getRecords() async {
    Database dbClient = await db;
    return await dbClient.query('records', orderBy: 'date DESC');
  }

  // Config for wage rate
  Future<double> getWageRate() async {
    Database dbClient = await db;
    List<Map> result = await dbClient.query('config', where: 'id = ?', whereArgs: [1]);
    return result.isNotEmpty ? result[0]['wage_rate'] : 0.0;
  }

  Future<int> updateWageRate(double rate) async {
    Database dbClient = await db;
    return await dbClient.update('config', {'wage_rate': rate}, where: 'id = ?', whereArgs: [1]);
  }
}