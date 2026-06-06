import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/catch.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bragmat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE catches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fish_type TEXT,
        length_cm INTEGER,
        notes TEXT,
        created_at TEXT,
        date_caught TEXT,
        image_path TEXT,
        photo_datetime TEXT,
        latitude REAL,
        longitude REAL
      )
    ''');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE catches ADD COLUMN date_caught TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE catches ADD COLUMN image_path TEXT');
      await db.execute('ALTER TABLE catches ADD COLUMN photo_datetime TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE catches ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE catches ADD COLUMN longitude REAL');
    }
  }

  // INSERT
  Future<int> insertCatch(Catch catchItem) async {
    final db = await instance.database;
    return await db.insert('catches', catchItem.toMap());
  }

  // READ
  Future<List<Catch>> getCatches() async {
    final db = await instance.database;
    final result = await db.query('catches');

    return result.map((json) => Catch.fromMap(json)).toList();
  }

  // UPDATE
  Future<int> updateCatch(Catch catchItem) async {
    final db = await instance.database;
    return await db.update(
      'catches',
      catchItem.toMap(),
      where: 'id = ?',
      whereArgs: [catchItem.id],
    );
  }

  // DELETE
  Future<int> deleteCatch(int id) async {
    final db = await instance.database;
    return await db.delete(
      'catches',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}