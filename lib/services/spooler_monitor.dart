import 'dart:async';
import 'dart:io';

/// Snapshot of one Windows print job's status, parsed from PowerShell output.
class SpoolerJobStatus {
  final int jobId;
  final String rawStatus; // e.g. "Printing", "Spooling", "Printed", "Paused", "Error"
  final int pagesPrinted;
  final int totalPages;

  SpoolerJobStatus({
    required this.jobId,
    required this.rawStatus,
    required this.pagesPrinted,
    required this.totalPages,
  });

  /// Layer 2 completion rule from PRD §7: a job is Completed when the spooler
  /// reports `Printed` with PagesPrinted == TotalPages.
  bool get isPrinted =>
      rawStatus.toLowerCase() == 'printed' &&
      totalPages > 0 &&
      pagesPrinted >= totalPages;

  bool get isError {
    final s = rawStatus.toLowerCase();
    return s == 'error' ||
        s == 'paperout' ||
        s == 'offline' ||
        s == 'blocked' ||
        s.contains('error') ||
        s.contains('paper') ||
        s.contains('offline');
  }

  bool get isPaperOut =>
      rawStatus.toLowerCase().contains('paper') ||
      rawStatus.toLowerCase() == 'paperout';

  bool get isOffline => rawStatus.toLowerCase().contains('offline');
}

/// The terminal outcome the monitor reports to the orchestrator.
enum JobOutcome { completed, failed, vanished, stillRunning, stuck }

/// Result the Queue Orchestrator consumes after each poll.
class MonitorResult {
  final JobOutcome outcome;
  final SpoolerJobStatus? status;
  final String? message;
  MonitorResult(this.outcome, {this.status, this.message});
}

/// Layer 2 (PRD §7): polls the specific Windows print job every ~1s and
/// declares Completed / Failed per the golden-rule completion check.
///
/// Uses PowerShell `Get-PrintJob` (PRD §10 MVP approach); can be swapped for
/// the `win32` package's EnumJobs/FFI later without touching the orchestrator.
class SpoolerMonitor {
  final Duration pollInterval;
  final Duration stuckTimeout;

  SpoolerMonitor({
    Duration? pollInterval,
    Duration? stuckTimeout,
  })  : pollInterval = pollInterval ?? const Duration(seconds: 1),
        stuckTimeout = stuckTimeout ?? const Duration(minutes: 3);

  /// Polls until [jobId] resolves to a terminal state, or the job vanishes
  /// from the queue, or it makes no page-progress for [stuckTimeout].
  ///
  /// Emits intermediate [SpoolerJobStatus] snapshots via [onProgress].
  Future<MonitorResult> watch({
    required String printerName,
    required int jobId,
    void Function(SpoolerJobStatus)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      // Non-Windows host: nothing to poll. Treat as vanished so the caller
      // (e.g. a dev/test) can decide. Real usage is Windows-only.
      return MonitorResult(JobOutcome.vanished, message: 'Non-Windows host.');
    }

    DateTime? lastProgressAt;
    int lastPagesPrinted = -1;
    final deadline = DateTime.now().add(const Duration(minutes: 30));

    while (DateTime.now().isBefore(deadline)) {
      final status = await _poll(printerName, jobId);
      if (status != null) {
        onProgress?.call(status);

        if (status.isPrinted) {
          return MonitorResult(JobOutcome.completed, status: status);
        }
        if (status.isError) {
          return MonitorResult(JobOutcome.failed,
              status: status,
              message: status.isPaperOut
                  ? 'Paper out on $printerName.'
                  : status.isOffline
                      ? 'Printer $printerName went offline.'
                      : 'Printer reported an error: ${status.rawStatus}.');
        }

        // Track page progress for stuck-job detection.
        if (status.pagesPrinted != lastPagesPrinted) {
          lastPagesPrinted = status.pagesPrinted;
          lastProgressAt ??= DateTime.now();
          lastProgressAt = DateTime.now();
        } else {
          lastProgressAt ??= DateTime.now();
          if (DateTime.now().difference(lastProgressAt!) > stuckTimeout) {
            return MonitorResult(JobOutcome.stuck,
                status: status,
                message: 'No page progress for '
                    '${stuckTimeout.inSeconds}s — job appears hung.');
          }
        }
      } else {
        // Job has left the queue. PRD §7: disappearance alone is never trusted
        // blindly (could be auto-deleted after an error). We report `vanished`
        // and let the orchestrator combine it with Layer 1's exit code.
        return MonitorResult(JobOutcome.vanished,
            message: 'Job $jobId left the queue.');
      }

      await Future.delayed(pollInterval);
    }

    return MonitorResult(JobOutcome.failed,
        message: 'Monitoring deadline exceeded.');
  }

  /// One poll cycle for [jobId] on [printerName]. Returns null if the job is
  /// no longer in the queue.
  Future<SpoolerJobStatus?> _poll(String printerName, int jobId) async {
    try {
      // Get-PrintJob outputs a table; we ask for explicit fields + CSV-ish form.
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Get-PrintJob -PrinterName "$printerName" '
            '| Where-Object { \$_.ID -eq $jobId } '
            '| Select-Object ID,JobStatus,PagesPrinted,TotalPages '
            r'| Format-List',
      ]);
      if (r.exitCode != 0) return null;
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return null;

      // Parse "Key : Value" lines from Format-List output.
      final map = <String, String>{};
      for (final line in out.split('\n')) {
        final idx = line.indexOf(':');
        if (idx <= 0) continue;
        final k = line.substring(0, idx).trim();
        final v = line.substring(idx + 1).trim();
        if (k.isNotEmpty) map[k] = v;
      }

      final id = int.tryParse(map['ID'] ?? '') ?? jobId;
      final status = (map['JobStatus'] ?? map['Status'] ?? '').trim();
      final printed = int.tryParse(map['PagesPrinted'] ?? '0') ?? 0;
      final total = int.tryParse(map['TotalPages'] ?? '0') ?? 0;

      if (status.isEmpty && printed == 0 && total == 0) return null;

      return SpoolerJobStatus(
        jobId: id,
        rawStatus: status.isEmpty ? 'Unknown' : status,
        pagesPrinted: printed,
        totalPages: total,
      );
    } catch (_) {
      return null;
    }
  }
}
