import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves the location of the bundled (or downloaded) SumatraPDF.exe.
///
/// Lookup order (PRD §10 — SumatraPDF bundled in app assets):
///  1. `SUMATRA_PDF_PATH` environment override (handy for ops / debugging).
///  2. `SumatraPDF.exe` sitting next to the running executable (bundled by CI).
///  3. `SumatraPDF.exe` in the app's support directory (downloaded on first run).
///  4. `assets/SumatraPDF.exe` relative to the working directory (dev builds).
class SumatraResolver {
  SumatraResolver._();

  /// Returns the resolved path if a SumatraPDF.exe exists, else null.
  static Future<String?> resolve() async {
    // 1. Env override.
    final env = Platform.environment['SUMATRA_PDF_PATH'];
    if (env != null && env.isNotEmpty && await File(env).exists()) {
      return env;
    }

    // 2. Next to the running executable.
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final beside = p.join(exeDir, 'SumatraPDF.exe');
    if (await File(beside).exists()) return beside;

    // 2b. One level up in a `bin/` style layout.
    final binLayout = p.join(exeDir, 'bin', 'SumatraPDF.exe');
    if (await File(binLayout).exists()) return binLayout;

    // 3. App support directory (downloaded on first run).
    try {
      final support = await getApplicationSupportDirectory();
      final downloaded = p.join(support.path, 'SumatraPDF.exe');
      if (await File(downloaded).exists()) return downloaded;
    } catch (_) {
      // path_provider may not be available in every context; ignore.
    }

    // 4. Dev / CI: assets/SumatraPDF.exe relative to cwd.
    final dev = p.join(Directory.current.path, 'assets', 'SumatraPDF.exe');
    if (await File(dev).exists()) return dev;

    return null;
  }

  /// Lists every printer name registered in Windows via SumatraPDF's own
  /// `-list-printers` output.
  ///
  /// ⚠️ This call has a hard 5-second timeout — SumatraPDF is supposed to
  /// print the list to stdout and exit immediately, but on some Windows
  /// configs it instead opens its GUI window and never exits (which would
  /// hang the caller forever). The timeout guarantees we never block the UI.
  ///
  /// Returns an empty list on timeout or any error. Callers should treat
  /// this as best-effort and fall back to WMI (see PrinterService).
  static Future<List<String>> listPrintersViaSumatra(String exePath) async {
    try {
      final result = await Process.run(exePath, ['-list-printers'])
          .timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return const [];
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      // Output format: "Printer '<name>'"
      return lines.map((l) {
        final m = RegExp(r"^Printer '(.+)'$").firstMatch(l);
        return m != null ? m.group(1)! : l;
      }).toList();
    } catch (_) {
      // Timeout or process error — caller falls back to WMI.
      return const [];
    }
  }
}
