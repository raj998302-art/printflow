import 'dart:io';

import 'package:printflow/models/printer_profile.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/utils/sumatra.dart';

/// Lists installed Windows printers (PRD Module 3 — Printer selector).
///
/// Strategy (PRD §10): try SumatraPDF's own `-list-printers` first (exact
/// spelling SumatraPDF will match against later). If that's unavailable or
/// empty, fall back through:
///   1. PowerShell `Get-Printer` (PrintManagement module — Windows 8+)
///   2. PowerShell `Get-CimInstance Win32_Printer` (WMI — all editions)
///   3. `wmic printer get name` (legacy fallback — pre-Windows 10)
///
/// This multi-fallback chain guarantees we find real installed printers on
/// every Windows edition, not just the ones with the PrintManagement module.
class PrinterService {
  PrinterService._();

  /// Returns the list of installed printers, with the system default flagged.
  static Future<List<PrinterProfile>> listPrinters({
    String? sumatraExePath,
  }) async {
    if (!Platform.isWindows) return const [];

    // 1. Try SumatraPDF first (if bundled).
    List<String> names = const [];
    if (sumatraExePath != null && await File(sumatraExePath).exists()) {
      try {
        names = await SumatraResolver.listPrintersViaSumatra(sumatraExePath);
      } catch (_) {
        names = const [];
      }
    }

    // 2. Fall back to PowerShell Get-Printer.
    if (names.isEmpty) {
      names = await _listViaGetPrinter();
    }

    // 3. Fall back to WMI via Get-CimInstance (available on ALL editions).
    if (names.isEmpty) {
      names = await _listViaWmiCim();
    }

    // 4. Last resort: wmic (legacy command, pre-Windows 10).
    if (names.isEmpty) {
      names = await _listViaWmic();
    }

    // De-duplicate (case-insensitive), preserving order.
    final seen = <String>{};
    final unique = <String>[];
    for (final n in names) {
      final key = n.trim().toLowerCase();
      if (key.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        unique.add(n.trim());
      }
    }

    // Detect the system default printer (best-effort).
    String? defaultName;
    try {
      defaultName = await _defaultPrinterName();
    } catch (_) {
      // best-effort
    }

    return unique
        .map((n) => PrinterProfile(
              name: n,
              isDefault: n.toLowerCase() ==
                  (defaultName?.toLowerCase() ?? n.toLowerCase() + '\u0000'),
            ))
        .toList();
  }

  /// PowerShell `Get-Printer` — requires the PrintManagement module
  /// (Windows 8+ / Server 2012+). Not available on some Home editions.
  static Future<List<String>> _listViaGetPrinter() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-Printer | Select-Object -ExpandProperty Name',
      ]);
      if (result.exitCode != 0) return const [];
      return _parseLines(result.stdout);
    } catch (_) {
      return const [];
    }
  }

  /// WMI via `Get-CimInstance -ClassName Win32_Printer` — works on ALL
  /// Windows editions (PRD §10 fallback).
  static Future<List<String>> _listViaWmiCim() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'Get-CimInstance -ClassName Win32_Printer | Select-Object -ExpandProperty Name',
      ]);
      if (result.exitCode != 0) return const [];
      return _parseLines(result.stdout);
    } catch (_) {
      return const [];
    }
  }

  /// `wmic printer get name` — legacy command-line tool, present on all
  /// Windows versions up to Windows 11 (deprecated but still functional).
  static Future<List<String>> _listViaWmic() async {
    try {
      final result = await Process.run('wmic', [
        'printer',
        'get',
        'name',
      ]);
      if (result.exitCode != 0) return const [];
      // wmic outputs a table with a "Name" header line; skip it.
      final lines = _parseLines(result.stdout);
      if (lines.isNotEmpty && lines.first.toLowerCase() == 'name') {
        return lines.skip(1).toList();
      }
      return lines;
    } catch (_) {
      return const [];
    }
  }

  static List<String> _parseLines(dynamic output) {
    if (output == null) return const [];
    return (output as String)
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  /// System default printer name (best-effort, via WMI).
  static Future<String?> _defaultPrinterName() async {
    try {
      // Modern approach: WMI Default flag.
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'(Get-CimInstance -ClassName Win32_Printer | Where-Object { $_.Default -eq $true } | Select-Object -First 1).Name',
      ]);
      if (result.exitCode == 0) {
        final name = (result.stdout as String).trim();
        if (name.isNotEmpty) return name;
      }
    } catch (_) {
      // fall through to wmic
    }
    // Legacy fallback: wmic.
    try {
      final result = await Process.run('wmic', [
        'printer',
        'where',
        'Default=TRUE',
        'get',
        'name',
      ]);
      if (result.exitCode == 0) {
        final lines = _parseLines(result.stdout);
        if (lines.isNotEmpty && lines.first.toLowerCase() == 'name') {
          final name = lines.skip(1).firstOrNull;
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (_) {
      // give up
    }
    return null;
  }

  /// Chooses the default color mode for a given printer by inspecting its
  /// capabilities. Heuristic — defaults to grayscale per shop practice.
  static Future<ColorMode> detectDefaultColorMode(String printerName) async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
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

  /// Opens the Windows **"Printing Preferences"** dialog for [printerName] —
  /// the native printer properties window where the operator selects paper
  /// tray, print quality, paper size, orientation, etc.
  ///
  /// Uses `rundll32 printui.dll,PrintUIEntry /e /n "<printer>"` which is the
  /// official Windows API for this dialog. The process blocks until the user
  /// closes the dialog, so callers can `await` it and then proceed.
  ///
  /// Settings saved here become the printer's **user-level defaults** for the
  /// current session. When SumatraPDF subsequently prints with `-print-to`
  /// (without overriding tray/paper-size via `-print-settings`), it uses these
  /// defaults — so the tray the operator picks here is the tray the batch
  /// actually prints from.
  ///
  /// Returns true if the dialog opened and closed normally, false on error.
  static Future<bool> openPrinterProperties(String printerName) async {
    if (!Platform.isWindows) return false;
    try {
      final result = await Process.run('rundll32', [
        'printui.dll,PrintUIEntry',
        '/e',
        '/n',
        printerName,
      ]);
      // rundll32 exit code isn't always reliable for dialog operations;
      // but a 0 or 1223 (user cancelled) both mean the dialog ran fine.
      return result.exitCode == 0 || result.exitCode == 1223;
    } catch (e) {
      return false;
    }
  }
}
