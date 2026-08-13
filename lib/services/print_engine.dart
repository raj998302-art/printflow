import 'dart:async';
import 'dart:io';

import 'package:printflow/models/print_job.dart';
import 'package:printflow/utils/page_range.dart';
import 'package:printflow/utils/sumatra.dart';

/// The result of firing a single job at SumatraPDF (PRD §7 Layer 1).
class PrintResult {
  /// SumatraPDF process exit code. 0 = command accepted, non-zero = rejected.
  final int exitCode;

  /// Captured stderr for diagnostics.
  final String stderr;

  /// The job id the spooler assigned, if we could capture it. May be null on
  /// Windows where capturing the freshly-created job id is best-effort.
  final int? spoolerJobId;

  /// True if the SumatraPDF binary itself was not found.
  final bool sumatraMissing;

  PrintResult({
    required this.exitCode,
    required this.stderr,
    this.spoolerJobId,
    this.sumatraMissing = false,
  });

  bool get accepted => exitCode == 0;
}

/// Fires one job at SumatraPDF and captures Layer 1 result (exit code) + the
/// resulting spooler job id for Layer 2 tracking (PRD §10).
///
/// Implements the process-level watchdog from PRD Module 5: if the SumatraPDF
/// process doesn't exit within [watchdogTimeoutSec], it is force-killed and
/// the job is treated as failed — a known real-world failure mode with silent
/// CLI printing on shared/network printers.
class PrintEngine {
  final String sumatraPath;

  PrintEngine(this.sumatraPath);

  /// Builds the exact SumatraPDF invocation for [job] (PRD §10):
  /// ```
  /// SumatraPDF.exe -print-to "<printer>" -silent -print-settings "<opts>" "<file>"
  /// ```
  List<String> buildArgs(PrintJob job, String printerName) {
    final args = <String>[
      '-print-to',
      printerName,
      '-silent',
    ];
    final pageRange = buildPageRange(job.pageCount, job.excludedPages);
    final settings = buildPrintSettings(
      copies: job.copies,
      colorMode: job.colorMode,
      duplex: job.duplex,
      pageRange: pageRange,
    );
    args.addAll(['-print-settings', settings]);
    args.add(job.filePath);
    return args;
  }

  /// Runs SumatraPDF for [job], with a hard process watchdog.
  /// On completion, tries to capture the freshly-spooled job id.
  Future<PrintResult> print({
    required PrintJob job,
    required String printerName,
    int watchdogTimeoutSec = 60,
  }) async {
    if (!await File(sumatraPath).exists()) {
      return PrintResult(
        exitCode: -1,
        stderr: 'SumatraPDF.exe not found at $sumatraPath. '
            'Download it from Settings, or place it next to PrintFlow.exe.',
        sumatraMissing: true,
      );
    }

    final args = buildArgs(job, printerName);
    final beforeJobIds = await _currentJobIds(printerName);

    final proc = await Process.start(sumatraPath, args);
    String stderr = '';
    proc.stderr.listen((data) {
      stderr += String.fromCharCodes(data);
    });

    int exitCode = -1;
    final timedOut = false;

    // Process-level watchdog: kill if it runs too long.
    final watchdog = Timer(
      Duration(seconds: watchdogTimeoutSec),
      () {
        try {
          proc.kill(ProcessSignal.sigkill);
        } catch (_) {
          // already exited
        }
      },
    );

    try {
      exitCode = await proc.exitCode;
    } catch (e) {
      stderr += '\nProcess error: $e';
    } finally {
      watchdog.cancel();
    }

    // Capture the spooler job id that just appeared (best-effort).
    int? spoolerJobId;
    if (exitCode == 0) {
      spoolerJobId = await _findNewJobId(printerName, beforeJobIds);
    }

    // ignore: unused_local_variable
    final _ = timedOut;

    return PrintResult(
      exitCode: exitCode,
      stderr: stderr,
      spoolerJobId: spoolerJobId,
      sumatraMissing: false,
    );
  }

  /// Snapshot of current job ids on [printerName] — to diff against after
  /// printing so we can identify the job we just created.
  Future<Set<int>> _currentJobIds(String printerName) async {
    if (!Platform.isWindows) return const {};
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-PrintJob -PrinterName "$printerName" '
            r'| Select-Object -ExpandProperty ID',
      ]);
      if (r.exitCode != 0) return const {};
      return (r.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => int.tryParse(l))
          .whereType<int>()
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<int?> _findNewJobId(String printerName, Set<int> before) async {
    final after = await _currentJobIds(printerName);
    final diff = after.difference(before);
    return diff.isEmpty ? null : diff.first;
  }

  /// Helper exposed for the Page Selector / Test Print button: validates the
  /// printer name against the exact spelling SumatraPDF expects.
  Future<bool> printerNameValid(String printerName) async {
    final names = await SumatraResolver.listPrintersViaSumatra(sumatraPath);
    return names.contains(printerName);
  }
}
