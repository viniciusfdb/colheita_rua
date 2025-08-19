import 'dart:async';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Simple repository to persist run tracking locally using SQLite.
///
/// This stores running sessions and their track points so that the
/// app can recover an ongoing run after being closed or killed.
class RunLocalRepository {
  RunLocalRepository._();
  static final RunLocalRepository instance = RunLocalRepository._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'runs.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE runs(id INTEGER PRIMARY KEY AUTOINCREMENT, startedAt INTEGER, endedAt INTEGER)'
        );
        await db.execute(
          'CREATE TABLE track_points(id INTEGER PRIMARY KEY AUTOINCREMENT, runId INTEGER, lat REAL, lng REAL, ts INTEGER)'
        );
      },
    );
    return _db!;
  }

  /// Starts a new run locally and returns its database id.
  Future<int> startRun(DateTime now) async {
    final db = await _database;
    return db.insert('runs', {'startedAt': now.millisecondsSinceEpoch});
  }

  /// Inserts a point for [runId].
  Future<void> insertPoint(int runId, LatLng p, DateTime ts) async {
    final db = await _database;
    await db.insert('track_points', {
      'runId': runId,
      'lat': p.latitude,
      'lng': p.longitude,
      'ts': ts.millisecondsSinceEpoch,
    });
  }

  /// Returns the unfinished run if available.
  Future<RunSession?> getUnfinishedRun() async {
    final db = await _database;
    final runs = await db.query('runs', where: 'endedAt IS NULL', limit: 1);
    if (runs.isEmpty) return null;
    final run = runs.first;
    final points = await db.query('track_points', where: 'runId = ?', whereArgs: [run['id']], orderBy: 'id');
    return RunSession(
      id: run['id'] as int,
      startedAt: DateTime.fromMillisecondsSinceEpoch(run['startedAt'] as int),
      points: points
          .map((e) => LatLng(e['lat'] as double, e['lng'] as double))
          .toList(),
    );
  }

  /// Reads points for [runId].
  Future<List<LatLng>> getPointsForRun(int runId) async {
    final db = await _database;
    final rows = await db.query('track_points', where: 'runId = ?', whereArgs: [runId], orderBy: 'id');
    return rows
        .map((e) => LatLng(e['lat'] as double, e['lng'] as double))
        .toList();
  }

  /// Marks [runId] as finished.
  Future<void> finishRun(int runId, DateTime endedAt) async {
    final db = await _database;
    await db.update(
      'runs',
      {'endedAt': endedAt.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  /// Deletes all data related to [runId].
  Future<void> deleteRun(int runId) async {
    final db = await _database;
    await db.delete('track_points', where: 'runId = ?', whereArgs: [runId]);
    await db.delete('runs', where: 'id = ?', whereArgs: [runId]);
  }
}

/// Value object representing a locally persisted run.
class RunSession {
  final int id;
  final DateTime startedAt;
  final List<LatLng> points;

  RunSession({required this.id, required this.startedAt, required this.points});
}

