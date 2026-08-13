/// Builds the SumatraPDF `-print-settings` page-range string from an exclusion list.
///
/// Example (PRD §10): a 10-page file with pages 3 and 7 excluded → "1-2,4-6,8-10".
/// Returns `null` when nothing is excluded, so the caller can omit `-print-settings`
/// entirely for that flag (per PRD §10).
String? buildPageRange(int totalPages, List<int> excludedPages) {
  if (excludedPages.isEmpty) return null;
  final excluded = excludedPages.where((p) => p >= 1 && p <= totalPages).toSet();
  if (excluded.isEmpty) return null;

  // Build the list of pages that WILL print, then collapse into ranges.
  final included = <int>[];
  for (var p = 1; p <= totalPages; p++) {
    if (!excluded.contains(p)) included.add(p);
  }
  if (included.isEmpty) return null;

  final ranges = <String>[];
  var start = included.first;
  var prev = start;
  for (var i = 1; i < included.length; i++) {
    final cur = included[i];
    if (cur == prev + 1) {
      prev = cur;
      continue;
    }
    ranges.add(start == prev ? '$start' : '$start-$prev');
    start = cur;
    prev = cur;
  }
  ranges.add(start == prev ? '$start' : '$start-$prev');
  return ranges.join(',');
}

/// Builds the full SumatraPDF `-print-settings` argument combining copies,
/// color, duplex and optional page range (PRD §10).
///
/// SumatraPDF syntax: `-print-settings "3x,duplex,color,1-2,4-6"`
String buildPrintSettings({
  required int copies,
  required ColorMode colorMode,
  required DuplexMode duplex,
  String? pageRange,
}) {
  final parts = <String>[];
  if (copies > 1) parts.add('${copies}x');
  parts.add(colorMode == ColorMode.color ? 'color' : 'monochrome');
  switch (duplex) {
    case DuplexMode.none:
      parts.add('simplex');
      break;
    case DuplexMode.longEdge:
      parts.add('duplex');
      break;
    case DuplexMode.shortEdge:
      parts.add('duplexshort');
      break;
  }
  if (pageRange != null && pageRange.isNotEmpty) parts.add(pageRange);
  return parts.join(',');
}
