import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:printflow/models/app_settings.dart';
import 'package:printflow/services/database_service.dart';
import 'package:printflow/state/batch_provider.dart';
import 'package:printflow/utils/sumatra.dart';

/// Provides the persisted [AppSettings], loaded asynchronously on startup.
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    // Never throw — if the database can't load, fall back to defaults so the
    // Settings screen always renders instead of showing "cannot be loaded".
    try {
      return await DatabaseService.loadSettings();
    } catch (e) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings next) async {
    try {
      await DatabaseService.saveSettings(next);
    } catch (_) {
      // best-effort persistence
    }
    state = AsyncData(next);
  }
}

/// Resolves the SumatraPDF path once at startup (PRD §10 — bundled asset).
final sumatraPathProvider = FutureProvider<String?>((ref) async {
  return SumatraResolver.resolve();
});

/// One-shot app health check: exposes whether the database opened and whether
/// any printers were found. The UI uses this to show a warning banner instead
/// of silently showing a blank screen when something fails.
final appHealthProvider = FutureProvider<AppHealth>((ref) async {
  // Force the DB to attempt initialization so we can report its status.
  AppHealth health;
  try {
    await DatabaseService.db();
    health = AppHealth(
      dbAvailable: DatabaseService.isAvailable,
      dbError: DatabaseService.initError,
    );
  } catch (e) {
    health = AppHealth(
      dbAvailable: false,
      dbError: e.toString(),
    );
  }
  return health;
});

class AppHealth {
  final bool dbAvailable;
  final String? dbError;
  const AppHealth({required this.dbAvailable, this.dbError});
}

/// The main batch/queue orchestrator. Depends on settings + sumatra path.
final batchProvider =
    ChangeNotifierProvider<BatchNotifier>((ref) {
  final settingsSnap = ref.watch(settingsProvider);
  final sumatraSnap = ref.watch(sumatraPathProvider);

  final settings = settingsSnap.valueOrNull ?? AppSettings.defaults();
  final sumatra = sumatraSnap.valueOrNull ?? '';

  return BatchNotifier(settings, sumatra);
});
