import 'package:pdfrx/pdfrx.dart';

/// PDF metadata + pre-flight validation (PRD §10 — `pdfx` / `pdfrx`).
///
/// Uses `pdfrx` because it has confirmed Windows desktop support and is
/// actively maintained against current Flutter. Page *rendering* for the
/// Page Selector thumbnail grid is done with pdfrx's `PdfPageView` widget
/// directly in the modal (see `page_selector_modal.dart`), which is the
/// idiomatic, well-tested rendering path.
class PdfService {
  PdfService._();

  /// Pre-flight validation (PRD Module 1). Corrupted & password-protected
  /// PDFs are rejected *before* they can jam a batch mid-run.
  static Future<PdfPreflightResult> preflight(String path) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path);
      final count = doc.pages.length;
      if (count == 0) {
        return PdfPreflightResult(ok: false, reason: 'PDF has no pages.');
      }
      return PdfPreflightResult(ok: true, pageCount: count);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('password') ||
          msg.contains('encrypted') ||
          msg.contains('Password') ||
          msg.contains('encrypt')) {
        return PdfPreflightResult(
            ok: false, reason: 'Password-protected PDF — remove password first.');
      }
      return PdfPreflightResult(ok: false, reason: 'Corrupted PDF: $msg');
    } finally {
      doc?.dispose();
    }
  }

  /// Returns the page count of [path], or 0 if the file can't be opened.
  static Future<int> pageCount(String path) async {
    final r = await preflight(path);
    return r.pageCount;
  }
}

class PdfPreflightResult {
  final bool ok;
  final String? reason;
  final int pageCount;
  const PdfPreflightResult({
    required this.ok,
    this.reason,
    this.pageCount = 0,
  });
}

class PdfPreflightException implements Exception {
  final String message;
  PdfPreflightException(this.message);
  @override
  String toString() => message;
}
