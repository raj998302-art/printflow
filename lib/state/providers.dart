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
  Future<AppSettings> build() => DatabaseService.loadSettings();

  Future<void> save(AppSettings next) async {
    await DatabaseService.saveSettings(next);
    state = AsyncData(next);
  }
}

/// Resolves the SumatraPDF path once at startup (PRD §10 — bundled asset).
final sumatraPathProvider = FutureProvider<String?>((ref) async {
  return SumatraResolver.resolve();
});

/// The main batch/queue orchestrator. Depends on settings + sumatra path.
final batchProvider =
    ChangeNotifierProvider<BatchNotifier>((ref) {
  final settingsSnap = ref.watch(settingsProvider);
  final sumatraSnap = ref.watch(sumatraPathProvider);

  final settings = settingsSnap.valueOrNull ?? AppSettings.defaults();
  final sumatra = sumatraSnap.valueOrNull ?? '';

  return BatchNotifier(settings, sumatra);
});
