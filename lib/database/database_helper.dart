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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE catches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fish_type TEXT,
        length_cm INTEGER,
        notes TEXT,
        created_at TEXT
      )
    ''');
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
}