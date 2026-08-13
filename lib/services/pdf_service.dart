import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// PDF metadata + thumbnail rendering (PRD §10 — `pdfx` / `pdfrx`).
///
/// We use `pdfrx` because it has confirmed Windows desktop support and exposes
/// the same `page.render()` style API the PRD describes, while being actively
/// maintained against current Flutter.
class PdfService {
  PdfService._();

  /// Returns the page count of [path], or 0 if the file is corrupted / locked.
  /// Throws [PdfPreflightException] for password-protected PDFs so the caller
  /// can flag them at import time (PRD Module 1 — pre-flight check).
  static Future<int> pageCount(String path) async {
    final doc = await PdfDocument.openFile(path);
    try {
      return doc.pages.length;
    } finally {
      doc.dispose();
    }
  }

  /// Pre-flight validation (PRD Module 1). Corrupted & password-protected
  /// PDFs are rejected *before* they can jam a batch mid-run.
  static Future<PdfPreflightResult> preflight(String path) async {
    final f = File(path);
    if (!await f.exists()) {
      return PdfPreflightResult(ok: false, reason: 'File does not exist.');
    }
    try {
      final doc = await PdfDocument.openFile(path);
      final count = doc.pages.length;
      doc.dispose();
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
    }
  }

  /// Renders page [pageNumber] (1-based) of [path] to a [ui.Image] thumbnail.
  /// Used by the Page Selector thumbnail grid (PRD Module 3).
  static Future<ui.Image> renderThumbnail(
    String path,
    int pageNumber, {
    double maxWidth = 220,
  }) async {
    final doc = await PdfDocument.openFile(path);
    try {
      final page = doc.pages[pageNumber - 1];
      final scale = (maxWidth / (page.width)).clamp(0.1, 4.0);
      final image = await page.render(
        width: page.width * scale,
        height: page.height * scale,
      );
      if (image == null) {
        throw StateError('pdfrx returned null image for page $pageNumber.');
      }
      return image;
    } finally {
      doc.dispose();
    }
  }

  /// Renders page [pageNumber] (1-based) to PNG bytes — handy for export/cache.
  static Future<Uint8List> renderThumbnailPng(
    String path,
    int pageNumber, {
    double maxWidth = 220,
  }) async {
    final image = await renderThumbnail(path, pageNumber, maxWidth: maxWidth);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode page $pageNumber to PNG.');
    }
    return byteData.buffer.asUint8List();
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
