import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:printflow/models/print_job.dart';
import 'package:printflow/state/providers.dart';

/// Page Selector modal (PRD §11 screen 2): a thumbnail grid of every page
/// in the PDF, rendered via pdfrx's `PdfPageView`. Tap a thumbnail to toggle
/// Excluded (greyed / struck through). "Select All" / "Deselect All" + a
/// live "X of Y pages will print" counter. Save is blocked if zero pages
/// remain selected.
class PageSelectorModal extends ConsumerStatefulWidget {
  final PrintJob job;
  const PageSelectorModal({super.key, required this.job});

  @override
  ConsumerState<PageSelectorModal> createState() => _PageSelectorModalState();
}

class _PageSelectorModalState extends ConsumerState<PageSelectorModal> {
  late Set<int> _excluded;
  PdfDocument? _doc;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _excluded = widget.job.excludedPages.toSet();
    _load();
  }

  Future<void> _load() async {
    try {
      _doc = await PdfDocument.openFile(widget.job.filePath);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _doc?.dispose();
    super.dispose();
  }

  int get _willPrint => widget.job.pageCount - _excluded.length;

  void _toggle(int page) {
    setState(() {
      if (_excluded.contains(page)) {
        _excluded.remove(page);
      } else {
        _excluded.add(page);
      }
    });
  }

  void _selectAll() => setState(() => _excluded.clear());

  void _deselectAll() => setState(() {
        _excluded =
            List.generate(widget.job.pageCount, (i) => i + 1).toSet();
      });

  Future<void> _save() async {
    if (_willPrint == 0) return; // blocked
    final notifier = ref.read(batchProvider.notifier);
    notifier.updateJob(widget.job.copyWith(
      excludedPages: _excluded.toList()..sort(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _willPrint > 0;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 920,
        height: 680,
        child: Scaffold(
          appBar: AppBar(
            title: Text('Pages — ${widget.job.fileName}'),
            actions: [
              TextButton(onPressed: _selectAll, child: const Text('Select All')),
              TextButton(
                  onPressed: _deselectAll, child: const Text('Deselect All')),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                        '${_willPrint} of ${widget.job.pageCount} pages will print',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: canSave ? Colors.green : Colors.red)),
                    const SizedBox(width: 16),
                    if (!canSave)
                      const Text('At least one page must remain included.',
                          style: TextStyle(color: Colors.red, fontSize: 12)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _body(context, canSave)),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                          'Excluded: ${(_excluded.toList()..sort()).isEmpty ? "none" : (_excluded.toList()..sort())}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: canSave ? _save : null,
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool canSave) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not open PDF:\n$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: widget.job.pageCount,
      itemBuilder: (context, i) {
        final page = i + 1;
        final excluded = _excluded.contains(page);
        return _ThumbnailTile(
          page: page,
          excluded: excluded,
          doc: _doc,
          onTap: () => _toggle(page),
        );
      },
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  final int page;
  final bool excluded;
  final PdfDocument? doc;
  final VoidCallback onTap;

  const _ThumbnailTile({
    required this.page,
    required this.excluded,
    required this.doc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: excluded
                ? Colors.red
                : Theme.of(context).colorScheme.outlineVariant,
            width: excluded ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: excluded ? Colors.red.withOpacity(0.08) : null,
        ),
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Opacity(
                  opacity: excluded ? 0.3 : 1,
                  child: doc != null
                      ? PdfPageView(
                          document: doc!,
                          pageNumber: page,
                        )
                      : const Center(child: Icon(Icons.broken_image)),
                ),
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('$page',
                    style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ),
            if (excluded)
              const Positioned.fill(
                child: Icon(Icons.close, size: 40, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
