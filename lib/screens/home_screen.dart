import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';

import 'package:printflow/models/print_job.dart';
import 'package:printflow/state/providers.dart';
import 'package:printflow/services/printer_service.dart';
import 'package:printflow/models/printer_profile.dart';
import 'package:printflow/screens/page_selector_modal.dart';

/// Home / Queue Builder screen (PRD §11 screen 1): drag-and-drop import +
/// sequence builder + print config + Start Batch.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _dragging = false;
  List<PrinterProfile> _printers = [];
  String? _selectedPrinter;
  int _copies = 1;
  ColorMode _color = ColorMode.grayscale;
  DuplexMode _duplex = DuplexMode.none;
  bool _loadingPrinters = true;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
  }

  Future<void> _loadPrinters() async {
    final sumatra = ref.read(sumatraPathProvider).valueOrNull;
    final printers = await PrinterService.listPrinters(sumatraExePath: sumatra);
    if (mounted) {
      setState(() {
        _printers = printers;
        if (printers.isEmpty) {
          _selectedPrinter = null;
        } else {
          final def = printers.firstWhere(
            (p) => p.isDefault,
            orElse: () => printers.first,
          );
          _selectedPrinter = def.name;
        }
        _loadingPrinters = false;
      });
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: true,
    );
    if (result != null && result.paths.isNotEmpty) {
      await ref
          .read(batchProvider.notifier)
          .importFiles(result.paths.whereType<String>().toList());
    }
  }

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Import every PDF from a folder',
    );
    if (dir == null) return;
    final entity = Directory(dir);
    final pdfs = <String>[];
    await for (final f in entity.list(recursive: false)) {
      if (f is File && f.path.toLowerCase().endsWith('.pdf')) {
        pdfs.add(f.path);
      }
    }
    if (pdfs.isNotEmpty) {
      await ref.read(batchProvider.notifier).importFiles(pdfs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(batchProvider);
    final running = batch.isRunning;

    return Stack(
      children: [
        DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (detail) async {
            setState(() => _dragging = false);
            final pdfs = detail.files
                .where((f) => f.path.toLowerCase().endsWith('.pdf'))
                .map((f) => f.path)
                .toList();
            if (pdfs.isNotEmpty) {
              await ref.read(batchProvider.notifier).importFiles(pdfs);
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Queue Builder'),
              actions: [
                IconButton(
                  tooltip: 'Sort by filename',
                  icon: const Icon(Icons.sort_by_alpha),
                  onPressed: running ? null : () => batch.sortByFileName(),
                ),
                IconButton(
                  tooltip: 'Sort by date added',
                  icon: const Icon(Icons.access_time),
                  onPressed: running ? null : () => batch.sortByDateAdded(),
                ),
                IconButton(
                  tooltip: 'Clear queue',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: running ? null : () => batch.clearDraft(),
                ),
              ],
            ),
            body: Column(
              children: [
                _dropZone(),
                const SizedBox(height: 8),
                Expanded(child: _jobList(batch, running)),
                const Divider(height: 1),
                _configBar(batch, running),
              ],
            ),
          ),
        ),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.15),
                child: const Center(
                  child: Icon(Icons.file_download, size: 72),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _dropZone() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.upload_file, size: 32),
                SizedBox(height: 4),
                Text('Drag & drop PDFs here'),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.folder_open),
              label: const Text('Browse Files'),
              onPressed: _pickFiles,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.drive_folder_upload),
              label: const Text('Import Folder'),
              onPressed: _pickFolder,
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobList(batch, bool running) {
    if (batch.jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('No files yet — drop in your PDFs above',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: batch.jobs.length,
      onReorder: (oldI, newI) => batch.reorder(oldI, newI),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, i) {
        final job = batch.jobs[i];
        return _JobRow(
          key: ValueKey(job.id),
          job: job,
          index: i,
          running: running,
          onPages: () => _openPageSelector(job),
          onRemove: () => batch.removeJob(job.id),
          onSeqChanged: (n) => batch.setSequenceNumber(job.id, n),
        );
      },
    );
  }

  Future<void> _openPageSelector(PrintJob job) async {
    await showDialog(
      context: context,
      builder: (_) => PageSelectorModal(job: job),
    );
    // Refresh the row's label after editing excluded pages.
    if (mounted) setState(() {});
  }

  Widget _configBar(batch, bool running) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Printer + settings row
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _printerSelector(),
              _stepper(
                label: 'Copies',
                value: _copies,
                min: 1,
                max: 20,
                onChanged: running
                    ? null
                    : (v) => setState(() => _copies = v),
              ),
              _segmented<ColorMode>(
                label: 'Color',
                value: _color,
                options: const [
                  (ColorMode.color, 'Color'),
                  (ColorMode.grayscale, 'B&W'),
                ],
                onChanged: running
                    ? null
                    : (v) => setState(() => _color = v),
              ),
              _segmented<DuplexMode>(
                label: 'Sides',
                value: _duplex,
                options: const [
                  (DuplexMode.none, '1-sided'),
                  (DuplexMode.longEdge, 'Duplex L'),
                  (DuplexMode.shortEdge, 'Duplex S'),
                ],
                onChanged: running
                    ? null
                    : (v) => setState(() => _duplex = v),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${batch.jobs.length} files • '
                '${batch.jobs.where((j) => j.preflightFailed).length} flagged',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Batch'),
                onPressed: (running || batch.jobs.isEmpty || _selectedPrinter == null)
                    ? null
                    : () => batch.startBatch(printerName: _selectedPrinter),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _printerSelector() {
    if (_loadingPrinters) {
      return const SizedBox(
        width: 220,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Detecting printers…'),
          ],
        ),
      );
    }
    return SizedBox(
      width: 260,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Printer',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        child: DropdownButton<String>(
          value: _selectedPrinter,
          isExpanded: true,
          underline: const SizedBox(),
          items: _printers
              .map((p) => DropdownMenuItem(
                    value: p.name,
                    child: Text(
                      p.name + (p.isDefault ? '  (default)' : ''),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedPrinter = v),
        ),
      ),
    );
  }

  Widget _stepper({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onChanged == null || value <= min
              ? null
              : () => onChanged(value - 1),
        ),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w600)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onChanged == null || value >= max
              ? null
              : () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _segmented<T>({
    required String label,
    required T value,
    required List<(T, String)> options,
    required ValueChanged<T>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 8),
        Wrap(
          spacing: 4,
          children: options.map((o) {
            final selected = o.$1 == value;
            return ChoiceChip(
              label: Text(o.$2),
              selected: selected,
              onSelected: onChanged == null
                  ? null
                  : (_) => onChanged(o.$1),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _JobRow extends StatelessWidget {
  final PrintJob job;
  final int index;
  final bool running;
  final VoidCallback onPages;
  final VoidCallback onRemove;
  final ValueChanged<int> onSeqChanged;

  const _JobRow({
    super.key,
    required this.job,
    required this.index,
    required this.running,
    required this.onPages,
    required this.onRemove,
    required this.onSeqChanged,
  });

  Color _statusColor(BuildContext c) {
    switch (job.status) {
      case JobStatus.completed:
        return Colors.green;
      case JobStatus.failed:
        return Colors.red;
      case JobStatus.printing:
        return Theme.of(c).colorScheme.primary;
      case JobStatus.skipped:
        return Colors.orange;
      case JobStatus.cancelled:
        return Colors.grey;
      default:
        return Theme.of(c).colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.drag_handle),
              ),
            ),
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: '${job.sequenceOrder}',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
                enabled: !running,
                onFieldSubmitted: (v) =>
                    onSeqChanged(int.tryParse(v) ?? job.sequenceOrder),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    children: [
                      Text(job.pageCountLabel,
                          style: TextStyle(
                              fontSize: 12, color: _statusColor(context))),
                      if (job.preflightFailed)
                        Text('⚠ ${job.preflightMessage ?? "pre-flight failed"}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.red)),
                      if (job.label.isNotEmpty)
                        Text('“${job.label}”',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.pages, size: 18),
              label: const Text('Pages'),
              onPressed: running ? null : onPages,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: running ? null : onRemove,
            ),
            const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _statusColor(context),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
