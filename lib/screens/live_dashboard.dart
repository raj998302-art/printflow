import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:printflow/models/print_job.dart';
import 'package:printflow/state/providers.dart';
import 'package:printflow/state/batch_provider.dart';

/// Live Print Dashboard (PRD §11 screen 3, Module 7): current job card,
/// overall batch progress, next-up preview, completed/failed lists, controls,
/// and the error modal (Retry / Skip / Cancel) on any Failed job.
class LiveDashboard extends ConsumerWidget {
  const LiveDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(batchProvider);

    if (!batch.hasBatch) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dashboard')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dashboard_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 8),
              Text('No active batch'),
            ],
          ),
        ),
      );
    }

    final showAlert = batch.pendingDecision != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(batch.batch?.name ?? 'Dashboard'),
        actions: [
          if (batch.isRunning)
            TextButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pause'),
              onPressed: () => batch.pause(),
            ),
          if (batch.isPaused && batch.pendingDecision == null)
            TextButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Resume'),
              onPressed: () => batch.resume(),
            ),
          TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cancel Batch'),
            onPressed: () => batch.cancelBatch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _progressCard(context, batch),
              const SizedBox(height: 16),
              if (batch.currentJob != null) _currentJobCard(context, batch),
              if (batch.currentJob != null) const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _listCard(context, 'Up Next',
                      batch.jobs.where((j) => j.status == JobStatus.pending).take(6).toList())),
                  const SizedBox(width: 16),
                  Expanded(child: _listCard(context, 'Completed',
                      batch.jobs.where((j) => j.status == JobStatus.completed).toList(),
                      color: Colors.green)),
                ],
              ),
              const SizedBox(height: 16),
              _listCard(context, 'Failed / Skipped',
                  batch.jobs.where((j) =>
                      j.status == JobStatus.failed ||
                      j.status == JobStatus.skipped).toList(),
                  color: Colors.red),
            ],
          ),
          if (showAlert) _errorOverlay(context, batch),
        ],
      ),
    );
  }

  Widget _progressCard(BuildContext context, BatchNotifier batch) {
    final total = batch.jobs.length;
    final done = batch.completedCount;
    final pct = total == 0 ? 0.0 : done / total;
    final remaining = batch.pendingCount;
    final failed = batch.failedCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('$done / $total completed',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (failed > 0)
                  Chip(
                    label: Text('$failed failed'),
                    backgroundColor: Colors.red.withOpacity(0.12),
                  ),
                if (remaining > 0) const SizedBox(width: 8),
                if (remaining > 0)
                  Chip(label: Text('$remaining remaining')),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: pct, minHeight: 12),
            const SizedBox(height: 6),
            Text('${(pct * 100).toStringAsFixed(0)}% • printer: ${batch.batch?.printerName ?? "-"}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _currentJobCard(BuildContext context, BatchNotifier batch) {
    final job = batch.currentJob!;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.print, size: 18),
                const SizedBox(width: 6),
                Text('Now Printing',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(job.fileName,
                style: const TextStyle(fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(
              'Page ${batch.currentPagesPrinted} of ${batch.currentTotalPages}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: batch.currentTotalPages == 0
                  ? 0
                  : batch.currentPagesPrinted / batch.currentTotalPages,
              minHeight: 10,
            ),
            const SizedBox(height: 6),
            Text('Spooler Job ID: ${job.spoolerJobId ?? "—"}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _listCard(BuildContext context, String title, List<PrintJob> items,
      {Color? color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color ?? Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('—', style: TextStyle(color: Colors.grey)),
              )
            else
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final j = items[i];
                    return ListTile(
                      dense: true,
                      leading: Text('#${j.sequenceOrder}'),
                      title: Text(j.fileName,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: j.errorMessage != null
                          ? Text(j.errorMessage!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 12))
                          : Text(j.pageCountLabel,
                              style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorOverlay(BuildContext context, BatchNotifier batch) {
    final d = batch.pendingDecision!;
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        alignment: Alignment.center,
        child: AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Print Queue Paused'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.job.fileName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(d.message),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => batch.cancelBatch(),
              child: const Text('Cancel Batch'),
            ),
            OutlinedButton(
              onPressed: () => batch.skipPending(),
              child: const Text('Skip File'),
            ),
            FilledButton(
              onPressed: () => batch.retryPending(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
