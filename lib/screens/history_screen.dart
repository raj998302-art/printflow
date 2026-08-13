import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';

import 'package:printflow/models/batch.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/services/database_service.dart';
import 'package:printflow/state/providers.dart';

/// History screen (PRD §11 screen 4, Module 8): past batches + per-job logs
/// + CSV export for cross-checking against the GST invoice sheet.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  List<Batch> _batches = [];
  final Map<String, List<PrintJob>> _jobs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final batches = await DatabaseService.listBatches();
    final jobs = <String, List<PrintJob>>{};
    for (final b in batches) {
      jobs[b.id] = await DatabaseService.jobsForBatch(b.id);
    }
    if (mounted) {
      setState(() {
        _batches = batches;
        _jobs.addAll(jobs);
        _loading = false;
      });
    }
  }

  Future<void> _exportCsv(Batch batch) async {
    final jobs = _jobs[batch.id] ?? [];
    final buf = StringBuffer();
    buf.writeln('Seq,FileName,Label,Pages,ExcludedPages,Copies,Color,Duplex,'
        'Status,StartedAt,CompletedAt,PagesPrinted,Error');
    for (final j in jobs) {
      buf.writeln([
        j.sequenceOrder,
        _csv(j.fileName),
        _csv(j.label),
        j.pageCount,
        _csv(j.excludedPages.join(';')),
        j.copies,
        j.colorMode.name,
        j.duplex.name,
        j.status.name,
        j.startedAt?.toIso8601String() ?? '',
        j.completedAt?.toIso8601String() ?? '',
        j.pagesPrinted,
        _csv(j.errorMessage ?? ''),
      ].join(','));
    }
    final dir = await getApplicationDocumentsDirectory();
    final fname = 'printflow_${batch.id}.csv';
    final file = File(p.join(dir.path, fname));
    await file.writeAsString(buf.toString());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported: ${file.path}')),
      );
    }
  }

  String _csv(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_batches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('History')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey),
              SizedBox(height: 8),
              Text('No batches yet'),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _batches.length,
        itemBuilder: (context, i) {
          final b = _batches[i];
          final jobs = _jobs[b.id] ?? [];
          return Card(
            child: ExpansionTile(
              title: Text(b.name),
              subtitle: Text(
                '${DateFormat('yyyy-MM-dd HH:mm').format(b.createdAt)} • '
                '${b.completedJobs}/${b.totalJobs} done • '
                '${b.failedJobs} failed • ${b.status.label}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Export CSV',
                onPressed: () => _exportCsv(b),
              ),
              children: [
                SizedBox(
                  height: 260,
                  child: jobs.isEmpty
                      ? const Center(child: Text('No jobs'))
                      : ListView.builder(
                          itemCount: jobs.length,
                          itemBuilder: (context, j) {
                            final job = jobs[j];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: _statusColor(job.status),
                                child: Text('${job.sequenceOrder}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 11)),
                              ),
                              title: Text(job.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${job.pageCountLabel} • ${job.status.label}'
                                '${job.errorMessage != null ? " • ${job.errorMessage}" : ""}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(JobStatus s) => switch (s) {
        JobStatus.completed => Colors.green,
        JobStatus.failed => Colors.red,
        JobStatus.skipped => Colors.orange,
        JobStatus.cancelled => Colors.grey,
        JobStatus.printing => Colors.blue,
        JobStatus.pending => Colors.grey.shade400,
      };
}
