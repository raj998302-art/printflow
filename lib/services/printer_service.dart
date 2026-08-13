import 'dart:io';

import 'package:printflow/models/printer_profile.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/utils/sumatra.dart';

/// Lists installed Windows printers (PRD Module 3 — Printer selector).
///
/// Strategy: prefer SumatraPDF's own `-list-printers` output (exact spelling
/// SumatraPDF will match against later, eliminating the "wrong printer name"
/// silent-fail). Falls back to PowerShell `Get-Printer` when SumatraPDF is not
/// yet bundled/downloaded.
class PrinterService {
  PrinterService._();

  /// Returns the list of printer names, with the system default flagged when
  /// we can detect it via WMI.
  static Future<List<PrinterProfile>> listPrinters({
    String? sumatraExePath,
  }) async {
    if (!Platform.isWindows) return const [];

    List<String> names;
    if (sumatraExePath != null && await File(sumatraExePath).exists()) {
      names = await SumatraResolver.listPrintersViaSumatra(sumatraExePath);
    } else {
      names = await _listViaPowerShell();
    }

    String? defaultName;
    try {
      defaultName = await _defaultPrinterName();
    } catch (_) {
      // ignore — default detection is best-effort.
    }

    return names
        .map((n) => PrinterProfile(
              name: n,
              isDefault: n == defaultName,
            ))
        .toList();
  }

  static Future<List<String>> _listViaPowerShell() async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'Get-Printer | Select-Object -ExpandProperty Name',
    ]);
    if (result.exitCode != 0) return const [];
    final out = (result.stdout as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return out;
  }

  /// System default printer name via WMI (best-effort).
  static Future<String?> _defaultPrinterName() async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      r'(Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1).Name',
    ]);
    if (result.exitCode != 0) return null;
    final name = (result.stdout as String).trim();
    return name.isEmpty ? null : name;
  }

  /// Chooses the default color mode for a given printer by inspecting its
  /// capabilities. Heuristic: most B&W-only printers advertise no color, but
  /// detection is best-effort — defaults to grayscale per shop practice.
  static Future<ColorMode> detectDefaultColorMode(String printerName) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-PrinterProperty -PrinterName "$printerName" | '
            r'Where-Object { $_.Name -like "*Color*" } | Select-Object -First 1 -ExpandProperty Value',
      ]);
      if (result.exitCode != 0) return ColorMode.grayscale;
      final v = (result.stdout as String).trim().toLowerCase();
      if (v.contains('color') && !v.contains('no')) return ColorMode.color;
    } catch (_) {
      // ignore
    }
    return ColorMode.grayscale;
  }
}
