import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

import 'package:printflow/models/batch.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/models/app_settings.dart';

/// SQLite persistence layer (PRD Module 10 — Crash Recovery & Persistence).
///
/// Every job's state is written as it changes, not just held in memory, so an
/// app/PC restart mid-batch lets PrintFlow offer "Resume from job #X".
class DatabaseService {
  static Database? _db;

  static Future<Database> db() async {
    if (_db != null) return _db!;

    // Desktop requires the FFI factory.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'printflow.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE batches(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            status TEXT NOT NULL,
            totalJobs INTEGER NOT NULL,
            completedJobs INTEGER NOT NULL,
            failedJobs INTEGER NOT NULL,
            printerName TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE jobs(
            id TEXT PRIMARY KEY,
            batchId TEXT NOT NULL,
            sequenceOrder INTEGER NOT NULL,
            filePath TEXT NOT NULL,
            fileName TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            pageCount INTEGER NOT NULL,
            excludedPages TEXT NOT NULL DEFAULT '',
            copies INTEGER NOT NULL DEFAULT 1,
            colorMode TEXT NOT NULL,
            duplex TEXT NOT NULL,
            status TEXT NOT NULL,
            spoolerJobId INTEGER,
            pagesPrinted INTEGER NOT NULL DEFAULT 0,
            retryCount INTEGER NOT NULL DEFAULT 0,
            startedAt TEXT,
            completedAt TEXT,
            errorMessage TEXT,
            preflightFailed INTEGER NOT NULL DEFAULT 0,
            preflightMessage TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE settings(
            id INTEGER PRIMARY KEY,
            pollIntervalMs INTEGER NOT NULL,
            stuckJobTimeoutSec INTEGER NOT NULL,
            processWatchdogTimeoutSec INTEGER NOT NULL,
            autoSkipEnabled INTEGER NOT NULL,
            autoSkipRetries INTEGER NOT NULL,
            soundAlertsEnabled INTEGER NOT NULL,
            defaultPrinterName TEXT,
            defaultCopies INTEGER NOT NULL DEFAULT 1,
            defaultColorMode TEXT NOT NULL,
            defaultDuplex TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ---- Batch ---------------------------------------------------------------

  static Future<void> upsertBatch(Batch b) async {
    final d = await db();
    await d.insert('batches', b.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Batch>> listBatches() async {
    final d = await db();
    final rows = await d.query('batches', orderBy: 'createdAt DESC');
    return rows.map(Batch.fromMap).toList();
  }

  static Future<Batch?> getBatch(String id) async {
    final d = await db();
    final rows = await d.query('batches', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Batch.fromMap(rows.first);
  }

  static Future<void> deleteBatch(String id) async {
    final d = await db();
    await d.delete('jobs', where: 'batchId = ?', whereArgs: [id]);
    await d.delete('batches', where: 'id = ?', whereArgs: [id]);
  }

  // ---- Jobs ----------------------------------------------------------------

  static Future<void> upsertJob(PrintJob j) async {
    final d = await db();
    await d.insert('jobs', j.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<PrintJob>> jobsForBatch(String batchId) async {
    final d = await db();
    final rows = await d.query('jobs',
        where: 'batchId = ?',
        whereArgs: [batchId],
        orderBy: 'sequenceOrder ASC');
    return rows.map(PrintJob.fromMap).toList();
  }

  // ---- Settings ------------------------------------------------------------

  static Future<AppSettings> loadSettings() async {
    final d = await db();
    final rows = await d.query('settings', where: 'id = ?', whereArgs: [1]);
    if (rows.isEmpty) {
      final def = AppSettings.defaults();
      await d.insert('settings', {'id': 1, ...def.toMap()});
      return def;
    }
    return AppSettings.fromMap(rows.first);
  }

  static Future<void> saveSettings(AppSettings s) async {
    final d = await db();
    await d.insert('settings', {'id': 1, ...s.toMap()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Looks for an interrupted batch (status = running/paused) to offer resume.
  static Future<Batch?> findInterruptedBatch() async {
    final d = await db();
    final rows = await d.query('batches',
        where: "status IN ('running','paused')",
        orderBy: 'createdAt DESC',
        limit: 1);
    return rows.isEmpty ? null : Batch.fromMap(rows.first);
  }

  /// Returns true if the platform can run this desktop store (Windows-only).
  static bool get isSupportedOnPlatform => Platform.isWindows;
}
