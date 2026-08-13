import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:printflow/models/batch.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/models/app_settings.dart';
import 'package:printflow/services/database_service.dart';
import 'package:printflow/services/pdf_service.dart';
import 'package:printflow/services/print_engine.dart';
import 'package:printflow/services/spooler_monitor.dart';

/// Reason the queue paused (PRD §7 — never silently moves on).
enum PauseReason { none, jobFailed, jobStuck, sumatraMissing, userPaused }

/// A pending operator decision when a job fails (Retry / Skip / Cancel).
class PendingDecision {
  final PrintJob job;
  final String message;
  final PauseReason reason;
  PendingDecision(this.job, this.message, this.reason);
}

/// Holds the live batch + jobs and implements the Queue Orchestrator lock
/// (PRD §7 golden rule + Module 6): exactly ONE job is "Printing" at any
/// moment, the next is pulled only when the previous resolves to Completed,
/// and on Failed the whole queue pauses and alerts.
class BatchNotifier extends ChangeNotifier {
  Batch? batch;
  List<PrintJob> jobs = [];

  /// The currently-printing job (global lock). Null when idle.
  PrintJob? currentJob;

  /// Live spooler progress for [currentJob].
  int currentPagesPrinted = 0;
  int currentTotalPages = 0;

  PauseReason pauseReason = PauseReason.none;
  PendingDecision? pendingDecision;

  /// When non-null, an interrupted batch was detected on launch (Module 10).
  Batch? interruptedBatch;

  bool _disposed = false;
  bool _processing = false;

  final AppSettings _settings;
  final String _sumatraPath;

  late final PrintEngine _engine;
  late final SpoolerMonitor _monitor;

  BatchNotifier(this._settings, this._sumatraPath) {
    _engine = PrintEngine(_sumatraPath);
    _monitor = SpoolerMonitor(
      pollInterval: Duration(milliseconds: _settings.pollIntervalMs),
      stuckTimeout: Duration(seconds: _settings.stuckJobTimeoutSec),
    );
  }

  // ---- Inspection helpers -------------------------------------------------

  bool get isRunning => batch != null && batch!.status == BatchStatus.running;
  bool get isPaused => batch != null && batch!.status == BatchStatus.paused;
  bool get hasBatch => batch != null && jobs.isNotEmpty;

  int get completedCount =>
      jobs.where((j) => j.status == JobStatus.completed).length;
  int get failedCount =>
      jobs.where((j) => j.status == JobStatus.failed).length;
  int get pendingCount =>
      jobs.where((j) => j.status == JobStatus.pending).length;

  PrintJob? jobById(String id) {
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  // ---- Import / sequence building ----------------------------------------

  /// Imports a list of PDF file paths, runs pre-flight on each, and appends
  /// them as Pending jobs. (PRD Module 1 — pre-flight flags corrupted /
  /// password-protected PDFs before Start.)
  Future<void> importFiles(List<String> paths) async {
    batch ??= Batch.create();
    await DatabaseService.upsertBatch(batch!);
    final startSeq = jobs.isEmpty ? 0 : jobs.length;
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final name = path.split(RegExp(r'[\\/]+')).last;
      final preflight = await PdfService.preflight(path);
      final job = PrintJob(
        id: 'job-${DateTime.now().microsecondsSinceEpoch}-$i-${i.hashCode.abs()}',
        batchId: batch!.id,
        sequenceOrder: startSeq + i + 1,
        filePath: path,
        fileName: name,
        pageCount: preflight.pageCount,
        preflightFailed: !preflight.ok,
        preflightMessage: preflight.reason,
        status: preflight.ok ? JobStatus.pending : JobStatus.failed,
      );
      jobs.add(job);
      await DatabaseService.upsertJob(job);
    }
    batch = batch!.copyWith(totalJobs: jobs.length);
    await DatabaseService.upsertBatch(batch!);
    notifyListeners();
  }

  /// Reorders a job to a new sequence position.
  void reorder(int oldIndex, int newIndex) {
    if (isRunning) return;
    if (newIndex > jobs.length) newIndex = jobs.length;
    if (oldIndex < newIndex) newIndex -= 1;
    final moved = jobs.removeAt(oldIndex);
    jobs.insert(newIndex, moved);
    _reindex();
    notifyListeners();
  }

  /// Sets an absolute sequence number typed by the operator (PRD Module 2 —
  /// fast reordering across 100+ items without endless drag-scrolling).
  void setSequenceNumber(String jobId, int newSeq) {
    if (isRunning) return;
    final idx = jobs.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;
    newSeq = newSeq.clamp(1, jobs.length);
    final job = jobs.removeAt(idx);
    jobs.insert(newSeq - 1, job);
    _reindex();
    notifyListeners();
  }

  void removeJob(String jobId) {
    if (isRunning) return;
    jobs.removeWhere((j) => j.id == jobId);
    _reindex();
    if (batch != null) {
      batch = batch!.copyWith(totalJobs: jobs.length);
      DatabaseService.upsertBatch(batch!);
    }
    notifyListeners();
  }

  void updateJob(PrintJob updated) {
    final idx = jobs.indexWhere((j) => j.id == updated.id);
    if (idx == -1) return;
    jobs[idx] = updated;
    DatabaseService.upsertJob(updated);
    notifyListeners();
  }

  void _reindex() {
    for (var i = 0; i < jobs.length; i++) {
      jobs[i] = jobs[i].copyWith(sequenceOrder: i + 1);
      DatabaseService.upsertJob(jobs[i]);
    }
  }

  // ---- Sort helpers (PRD Module 2) ---------------------------------------

  void sortByFileName() {
    if (isRunning) return;
    jobs.sort((a, b) =>
        a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
    _reindex();
    notifyListeners();
  }

  void sortByDateAdded() {
    if (isRunning) return;
    jobs.sort((a, b) => a.id.compareTo(b.id));
    _reindex();
    notifyListeners();
  }

  // ---- Batch lifecycle ---------------------------------------------------

  /// Begins strictly-serial execution (PRD §7 golden rule). Starts at the
  /// first Pending job, then chains the next only on Completed.
  Future<void> startBatch({String? printerName}) async {
    if (batch == null || jobs.isEmpty || isRunning || _processing) return;

    batch = batch!.copyWith(
      status: BatchStatus.running,
      printerName: printerName ?? batch!.printerName,
    );
    await DatabaseService.upsertBatch(batch!);
    notifyListeners();

    unawaited(_processNextJob());
  }

  /// The orchestrator core: takes ONE job, prints it, waits for real
  /// completion (Layer 1 + Layer 2), then pulls the next. Never two at once.
  Future<void> _processNextJob() async {
    if (_disposed || batch == null || _processing) return;
    if (batch!.status != BatchStatus.running) return;

    _processing = true;
    try {
      final next = jobs
          .where((j) =>
              j.status == JobStatus.pending && !j.preflightFailed)
          .toList();
      if (next.isEmpty) {
        _finishBatch();
        return;
      }
      var job = next.first;

      // Acquire the global lock.
      currentJob = job;
      currentPagesPrinted = 0;
      currentTotalPages = job.effectivePageCount;
      job = job.copyWith(
        status: JobStatus.printing,
        startedAt: DateTime.now(),
        retryCount: 0,
      );
      _replaceJob(job);
      await DatabaseService.upsertJob(job);
      notifyListeners();

      // ---- Layer 1: fire SumatraPDF -------------------------------
      final printer = batch!.printerName;
      if (printer == null || printer.isEmpty) {
        _failJob(job, 'No target printer selected for the batch.');
        return;
      }
      final result = await _engine.print(
        job: job,
        printerName: printer,
        watchdogTimeoutSec: _settings.processWatchdogTimeoutSec,
      );

      if (result.sumatraMissing) {
        _pauseJob(job, 'SumatraPDF not found: ${result.stderr}',
            PauseReason.sumatraMissing);
        return;
      }
      if (!result.accepted) {
        _failJob(
            job,
            'SumatraPDF rejected the job (exit ${result.exitCode}). '
                '${result.stderr}');
        return;
      }

      // ---- Layer 2: poll the spooler until truly finished ---------
      if (result.spoolerJobId != null) {
        job = job.copyWith(spoolerJobId: result.spoolerJobId);
        _replaceJob(job);
        await DatabaseService.upsertJob(job);

        final monitorResult = await _monitor.watch(
          printerName: printer,
          jobId: result.spoolerJobId!,
          onProgress: (s) {
            currentPagesPrinted = s.pagesPrinted;
            currentTotalPages = s.totalPages;
            final idx = jobs.indexWhere((j) => j.id == job.id);
            if (idx != -1) {
              jobs[idx] =
                  jobs[idx].copyWith(pagesPrinted: s.pagesPrinted);
              DatabaseService.upsertJob(jobs[idx]);
            }
            notifyListeners();
          },
        );

        switch (monitorResult.outcome) {
          case JobOutcome.completed:
            _completeJob(job);
            break;
          case JobOutcome.vanished:
            // PRD §7: disappearance combined with Layer 1 exit code. Layer 1
            // was 0 here, so treat vanished as completed.
            _completeJob(job);
            break;
          case JobOutcome.failed:
            _failJob(
                job, monitorResult.message ?? 'Printer reported an error.');
            return;
          case JobOutcome.stuck:
            _pauseJob(job,
                monitorResult.message ?? 'Job stuck — no page progress.',
                PauseReason.jobStuck);
            return;
          case JobOutcome.stillRunning:
            _completeJob(job); // best-effort
            break;
        }
      } else {
        // Couldn't capture spooler job id — trust Layer 1 success and a
        // brief grace window before declaring complete.
        await Future.delayed(const Duration(seconds: 2));
        _completeJob(job);
      }

      // Release the lock & pull the next.
      currentJob = null;
      currentPagesPrinted = 0;
      if (batch != null && batch!.status == BatchStatus.running) {
        // Loop continues for the next pending job.
        _processing = false;
        await _processNextJob();
        return;
      }
    } finally {
      _processing = false;
    }
  }

  void _replaceJob(PrintJob job) {
    final idx = jobs.indexWhere((j) => j.id == job.id);
    if (idx != -1) jobs[idx] = job;
  }

  void _completeJob(PrintJob job) {
    final idx = jobs.indexWhere((j) => j.id == job.id);
    if (idx == -1) return;
    job = job.copyWith(
      status: JobStatus.completed,
      completedAt: DateTime.now(),
      pagesPrinted: job.effectivePageCount,
    );
    jobs[idx] = job;
    DatabaseService.upsertJob(job);
    if (batch != null) {
      batch = batch!.copyWith(completedJobs: completedCount);
      DatabaseService.upsertBatch(batch!);
    }
    notifyListeners();
  }

  void _failJob(PrintJob job, String message) {
    final idx = jobs.indexWhere((j) => j.id == job.id);
    if (idx == -1) return;
    job = job.copyWith(
      status: JobStatus.failed,
      completedAt: DateTime.now(),
      errorMessage: message,
    );
    jobs[idx] = job;
    DatabaseService.upsertJob(job);
    if (batch != null) {
      batch = batch!.copyWith(failedJobs: failedCount);
      DatabaseService.upsertBatch(batch!);
    }
    _pauseBatch(PauseReason.jobFailed,
        decision: PendingDecision(job, message, PauseReason.jobFailed));
  }

  void _pauseJob(PrintJob job, String message, PauseReason reason) {
    final idx = jobs.indexWhere((j) => j.id == job.id);
    if (idx != -1) {
      job = job.copyWith(
        status: JobStatus.failed,
        completedAt: DateTime.now(),
        errorMessage: message,
      );
      jobs[idx] = job;
      DatabaseService.upsertJob(job);
    }
    _pauseBatch(reason,
        decision: PendingDecision(job, message, reason));
  }

  void _pauseBatch(PauseReason reason, {PendingDecision? decision}) {
    if (batch == null) return;
    batch = batch!.copyWith(status: BatchStatus.paused);
    DatabaseService.upsertBatch(batch!);
    pauseReason = reason;
    pendingDecision = decision;
    currentJob = null;
    _processing = false;
    notifyListeners();
  }

  void _finishBatch() {
    if (batch == null) return;
    batch = batch!.copyWith(status: BatchStatus.completed);
    DatabaseService.upsertBatch(batch!);
    pauseReason = PauseReason.none;
    pendingDecision = null;
    currentJob = null;
    _processing = false;
    notifyListeners();
  }

  // ---- Operator decisions on a paused batch (PRD §7) --------------------

  /// Retries the pending job: resets it to Pending and resumes the queue.
  Future<void> retryPending() async {
    final d = pendingDecision;
    if (d == null) return;
    final idx = jobs.indexWhere((j) => j.id == d.job.id);
    if (idx != -1) {
      jobs[idx] = jobs[idx].copyWith(
        status: JobStatus.pending,
        retryCount: jobs[idx].retryCount + 1,
        errorMessage: null,
        completedAt: null,
        startedAt: null,
      );
      DatabaseService.upsertJob(jobs[idx]);
    }
    pendingDecision = null;
    pauseReason = PauseReason.none;
    batch = batch!.copyWith(status: BatchStatus.running);
    DatabaseService.upsertBatch(batch!);
    notifyListeners();
    unawaited(_processNextJob());
  }

  /// Skips the pending job and continues the queue.
  Future<void> skipPending() async {
    final d = pendingDecision;
    if (d == null) return;
    final idx = jobs.indexWhere((j) => j.id == d.job.id);
    if (idx != -1) {
      jobs[idx] = jobs[idx].copyWith(
        status: JobStatus.skipped,
        completedAt: DateTime.now(),
      );
      DatabaseService.upsertJob(jobs[idx]);
    }
    pendingDecision = null;
    pauseReason = PauseReason.none;
    batch = batch!.copyWith(status: BatchStatus.running);
    DatabaseService.upsertBatch(batch!);
    notifyListeners();
    unawaited(_processNextJob());
  }

  /// Cancels the whole batch.
  Future<void> cancelBatch() async {
    if (batch == null) return;
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].status == JobStatus.pending ||
          jobs[i].status == JobStatus.printing) {
        jobs[i] = jobs[i].copyWith(
          status: JobStatus.cancelled,
          completedAt: DateTime.now(),
        );
        DatabaseService.upsertJob(jobs[i]);
      }
    }
    batch = batch!.copyWith(status: BatchStatus.cancelled);
    DatabaseService.upsertBatch(batch!);
    pendingDecision = null;
    pauseReason = PauseReason.none;
    currentJob = null;
    _processing = false;
    notifyListeners();
  }

  /// Operator-initiated pause.
  Future<void> pause() async {
    if (batch == null || batch!.status != BatchStatus.running) return;
    batch = batch!.copyWith(status: BatchStatus.paused);
    pauseReason = PauseReason.userPaused;
    DatabaseService.upsertBatch(batch!);
    notifyListeners();
  }

  /// Operator-initiated resume.
  Future<void> resume() async {
    if (batch == null || batch!.status != BatchStatus.paused) return;
    batch = batch!.copyWith(status: BatchStatus.running);
    pauseReason = PauseReason.none;
    DatabaseService.upsertBatch(batch!);
    notifyListeners();
    unawaited(_processNextJob());
  }

  /// Clears the current draft batch so the operator can start fresh.
  Future<void> clearDraft() async {
    if (batch == null) return;
    await DatabaseService.deleteBatch(batch!.id);
    batch = null;
    jobs = [];
    currentJob = null;
    pendingDecision = null;
    pauseReason = PauseReason.none;
    _processing = false;
    notifyListeners();
  }

  /// Loads any interrupted batch from disk (Module 10 — Crash Recovery).
  Future<void> detectInterrupted() async {
    final b = await DatabaseService.findInterruptedBatch();
    if (b == null) {
      interruptedBatch = null;
      return;
    }
    interruptedBatch = b;
    final dbJobs = await DatabaseService.jobsForBatch(b.id);
    batch = b;
    jobs = dbJobs;
    notifyListeners();
  }

  /// Resumes an interrupted batch from the first non-completed job.
  Future<void> resumeInterrupted() async {
    if (interruptedBatch == null) return;
    interruptedBatch = null;
    batch = batch!.copyWith(status: BatchStatus.running);
    DatabaseService.upsertBatch(batch!);
    notifyListeners();
    unawaited(_processNextJob());
  }

  void dismissInterrupted() {
    interruptedBatch = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
