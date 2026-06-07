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
      version: 7,
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
        longitude REAL,
        location TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE fish_types (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
      )
    ''');

    // Insert default fish types
    await db.insert('fish_types', {'name': 'Barramundi'});
    await db.insert('fish_types', {'name': 'Mangrove Jack'});
    await db.insert('fish_types', {'name': 'Saratoga'});
    await db.insert('fish_types', {'name': 'Jewfish'});
    await db.insert('fish_types', {'name': 'Queenfish'});
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
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE fish_types (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT UNIQUE NOT NULL
        )
      ''');
      await db.insert('fish_types', {'name': 'Barramundi'});
      await db.insert('fish_types', {'name': 'Mangrove Jack'});
      await db.insert('fish_types', {'name': 'Saratoga'});
      await db.insert('fish_types', {'name': 'Jewfish'});
      await db.insert('fish_types', {'name': 'Queenfish'});
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
    }
    if (oldVersion < 7) {
      // Add location column if it doesn't exist (for databases at version 6 without location)
      try {
        await db.execute('ALTER TABLE catches ADD COLUMN location TEXT');
      } catch (e) {
        // Column might already exist, ignore error
      }
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

  // FISH TYPES
  Future<List<String>> getFishTypes() async {
    final db = await instance.database;
    final result = await db.query('fish_types', orderBy: 'name');
    return result.map((json) => json['name'] as String).toList();
  }

  Future<int> insertFishType(String name) async {
    final db = await instance.database;
    try {
      return await db.insert('fish_types', {'name': name});
    } catch (e) {
      // If fish type already exists, return -1
      return -1;
    }
  }

  Future<bool> isFishTypeUsed(String name) async {
    final db = await instance.database;
    final result = await db.query(
      'catches',
      where: 'fish_type = ?',
      whereArgs: [name],
    );
    return result.isNotEmpty;
  }

  Future<int> updateFishType(String oldName, String newName) async {
    final db = await instance.database;
    // Update the fish type name in fish_types table
    final fishTypeResult = await db.update(
      'fish_types',
      {'name': newName},
      where: 'name = ?',
      whereArgs: [oldName],
    );
    // Update all catches that use this fish type
    await db.update(
      'catches',
      {'fish_type': newName},
      where: 'fish_type = ?',
      whereArgs: [oldName],
    );
    return fishTypeResult;
  }

  Future<int> deleteFishType(String name) async {
    final db = await instance.database;
    return await db.delete(
      'fish_types',
      where: 'name = ?',
      whereArgs: [name],
    );
  }
}