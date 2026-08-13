import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Batch;
import 'package:sqflite/sqflite.dart' hide Batch;

import 'package:printflow/models/batch.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/models/app_settings.dart';

/// SQLite persistence layer (PRD Module 10 — Crash Recovery & Persistence).
///
/// Every job's state is written as it changes, not just held in memory, so an
/// app/PC restart mid-batch lets PrintFlow offer "Resume from job #X".
///
/// This layer is **crash-proof**: if the sqlite3 native library fails to load
/// (missing DLL, antivirus, permissions), every method degrades gracefully to
/// empty/default values instead of throwing. The app keeps working for the
/// core print flow — only persistence is temporarily disabled.
class DatabaseService {
  static Database? _db;
  static bool _initAttempted = false;
  static bool _dbAvailable = false;
  static String? _initError;

  /// True if the database opened successfully. When false, all read/write
  /// methods return empty/default values and writes are silently skipped.
  static bool get isAvailable => _dbAvailable;

  /// The last initialization error (for diagnostics / UI warnings). Null when
  /// the DB is healthy.
  static String? get initError => _initError;

  static Future<Database> db() async {
    if (_db != null && _dbAvailable) return _db!;

    if (!_initAttempted) {
      _initAttempted = true;
      try {
        // Desktop requires the FFI factory + the native sqlite3 library
        // (bundled by the `sqlite3_flutter_libs` package).
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
        _dbAvailable = true;
        _initError = null;
      } catch (e) {
        _dbAvailable = false;
        _initError = e.toString();
        _db = null;
        // The app continues without persistence — UI must not crash.
      }
    }

    if (!_dbAvailable || _db == null) {
      throw StateError(
          'Database unavailable: ${_initError ?? "not initialized"}');
    }
    return _db!;
  }

  // ---- Batch ---------------------------------------------------------------

  static Future<void> upsertBatch(Batch b) async {
    if (!_dbAvailable) return;
    try {
      final d = await db();
      await d.insert('batches', b.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // Persistence is best-effort — never break the print flow.
    }
  }

  static Future<List<Batch>> listBatches() async {
    if (!_dbAvailable) return const [];
    try {
      final d = await db();
      final rows = await d.query('batches', orderBy: 'createdAt DESC');
      return rows.map(Batch.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<Batch?> getBatch(String id) async {
    if (!_dbAvailable) return null;
    try {
      final d = await db();
      final rows =
          await d.query('batches', where: 'id = ?', whereArgs: [id]);
      return rows.isEmpty ? null : Batch.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteBatch(String id) async {
    if (!_dbAvailable) return;
    try {
      final d = await db();
      await d.delete('jobs', where: 'batchId = ?', whereArgs: [id]);
      await d.delete('batches', where: 'id = ?', whereArgs: [id]);
    } catch (_) {
      // best-effort
    }
  }

  // ---- Jobs ----------------------------------------------------------------

  static Future<void> upsertJob(PrintJob j) async {
    if (!_dbAvailable) return;
    try {
      final d = await db();
      await d.insert('jobs', j.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // best-effort
    }
  }

  static Future<List<PrintJob>> jobsForBatch(String batchId) async {
    if (!_dbAvailable) return const [];
    try {
      final d = await db();
      final rows = await d.query('jobs',
          where: 'batchId = ?',
          whereArgs: [batchId],
          orderBy: 'sequenceOrder ASC');
      return rows.map(PrintJob.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  // ---- Settings ------------------------------------------------------------

  static Future<AppSettings> loadSettings() async {
    if (!_dbAvailable) {
      // Return defaults without throwing — the app must still launch.
      return AppSettings.defaults();
    }
    try {
      final d = await db();
      final rows = await d.query('settings', where: 'id = ?', whereArgs: [1]);
      if (rows.isEmpty) {
        final def = AppSettings.defaults();
        await d.insert('settings', {'id': 1, ...def.toMap()});
        return def;
      }
      return AppSettings.fromMap(rows.first);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  static Future<void> saveSettings(AppSettings s) async {
    if (!_dbAvailable) return;
    try {
      final d = await db();
      await d.insert('settings', {'id': 1, ...s.toMap()},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {
      // best-effort
    }
  }

  /// Looks for an interrupted batch (status = running/paused) to offer resume.
  static Future<Batch?> findInterruptedBatch() async {
    if (!_dbAvailable) return null;
    try {
      final d = await db();
      final rows = await d.query('batches',
          where: "status IN ('running','paused')",
          orderBy: 'createdAt DESC',
          limit: 1);
      return rows.isEmpty ? null : Batch.fromMap(rows.first);
    } catch (_) {
      return null;
    }
  }

  /// Returns true if the platform is Windows (the printing/spooler target).
  static bool get isSupportedOnPlatform => Platform.isWindows;
}
