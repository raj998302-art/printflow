/// Per-job lifecycle status, matching the PRD §7 state machine.
enum JobStatus {
  pending,
  printing,
  completed,
  failed,
  skipped,
  cancelled;

  String get label => switch (this) {
        JobStatus.pending => 'Pending',
        JobStatus.printing => 'Printing',
        JobStatus.completed => 'Completed',
        JobStatus.failed => 'Failed',
        JobStatus.skipped => 'Skipped',
        JobStatus.cancelled => 'Cancelled',
      };
}

/// Color mode for a print job.
enum ColorMode {
  color,
  grayscale;

  String get label => switch (this) {
        ColorMode.color => 'Color',
        ColorMode.grayscale => 'B&W',
      };
}

/// Duplex (double-sided) mode.
enum DuplexMode {
  none,
  longEdge,
  shortEdge;

  String get label => switch (this) {
        DuplexMode.none => 'Single-sided',
        DuplexMode.longEdge => 'Duplex (long edge)',
        DuplexMode.shortEdge => 'Duplex (short edge)',
      };
}

/// A single file within a batch, queued for printing.
///
/// Mirrors the PrintJob model in PRD §9, including [excludedPages] which powers
/// the per-page exclusion feature (Module 3).
class PrintJob {
  final String id;
  final String batchId;
  int sequenceOrder;
  final String filePath;
  final String fileName;
  String label;

  /// Raw page count of the source PDF.
  int pageCount;

  /// 1-based page numbers the operator excluded from printing.
  List<int> excludedPages;

  int copies;
  ColorMode colorMode;
  DuplexMode duplex;

  JobStatus status;
  int? spoolerJobId;
  int pagesPrinted;
  int retryCount;

  DateTime? startedAt;
  DateTime? completedAt;
  String? errorMessage;

  /// True if the PDF failed pre-flight (corrupted / password-protected).
  bool preflightFailed;
  String? preflightMessage;

  PrintJob({
    required this.id,
    required this.batchId,
    required this.sequenceOrder,
    required this.filePath,
    required this.fileName,
    this.label = '',
    required this.pageCount,
    this.excludedPages = const [],
    this.copies = 1,
    this.colorMode = ColorMode.grayscale,
    this.duplex = DuplexMode.none,
    this.status = JobStatus.pending,
    this.spoolerJobId,
    this.pagesPrinted = 0,
    this.retryCount = 0,
    this.startedAt,
    this.completedAt,
    this.errorMessage,
    this.preflightFailed = false,
    this.preflightMessage,
  });

  /// Page count that will actually be submitted to the printer.
  int get effectivePageCount => pageCount - excludedPages.length;

  /// Human readable page summary, e.g. "8/10 pages".
  String get pageCountLabel =>
      excludedPages.isEmpty ? '$pageCount pages' : '${effectivePageCount}/$pageCount pages';

  Duration? get elapsed => (startedAt != null)
      ? (completedAt ?? DateTime.now()).difference(startedAt!)
      : null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'batchId': batchId,
        'sequenceOrder': sequenceOrder,
        'filePath': filePath,
        'fileName': fileName,
        'label': label,
        'pageCount': pageCount,
        'excludedPages': excludedPages.join(','),
        'copies': copies,
        'colorMode': colorMode.name,
        'duplex': duplex.name,
        'status': status.name,
        'spoolerJobId': spoolerJobId,
        'pagesPrinted': pagesPrinted,
        'retryCount': retryCount,
        'startedAt': startedAt?.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'errorMessage': errorMessage,
        'preflightFailed': preflightFailed ? 1 : 0,
        'preflightMessage': preflightMessage,
      };

  factory PrintJob.fromMap(Map<String, dynamic> m) {
    final excluded = (m['excludedPages'] as String?) ?? '';
    return PrintJob(
      id: m['id'] as String,
      batchId: m['batchId'] as String,
      sequenceOrder: m['sequenceOrder'] as int,
      filePath: m['filePath'] as String,
      fileName: m['fileName'] as String,
      label: (m['label'] as String?) ?? '',
      pageCount: m['pageCount'] as int,
      excludedPages: excluded.isEmpty
          ? const []
          : excluded.split(',').map((e) => int.parse(e.trim())).toList(),
      copies: m['copies'] as int,
      colorMode: ColorMode.values.byName(m['colorMode'] as String),
      duplex: DuplexMode.values.byName(m['duplex'] as String),
      status: JobStatus.values.byName(m['status'] as String),
      spoolerJobId: m['spoolerJobId'] as int?,
      pagesPrinted: m['pagesPrinted'] as int,
      retryCount: m['retryCount'] as int,
      startedAt: (m['startedAt'] as String?)?.let(DateTime.parse),
      completedAt: (m['completedAt'] as String?)?.let(DateTime.parse),
      errorMessage: m['errorMessage'] as String?,
      preflightFailed: (m['preflightFailed'] as int?) == 1,
      preflightMessage: m['preflightMessage'] as String?,
    );
  }

  PrintJob copyWith({
    int? sequenceOrder,
    String? label,
    int? pageCount,
    List<int>? excludedPages,
    int? copies,
    ColorMode? colorMode,
    DuplexMode? duplex,
    JobStatus? status,
    int? spoolerJobId,
    int? pagesPrinted,
    int? retryCount,
    DateTime? startedAt,
    DateTime? completedAt,
    String? errorMessage,
    bool? preflightFailed,
    String? preflightMessage,
  }) =>
      PrintJob(
        id: id,
        batchId: batchId,
        sequenceOrder: sequenceOrder ?? this.sequenceOrder,
        filePath: filePath,
        fileName: fileName,
        label: label ?? this.label,
        pageCount: pageCount ?? this.pageCount,
        excludedPages: excludedPages ?? List.of(this.excludedPages),
        copies: copies ?? this.copies,
        colorMode: colorMode ?? this.colorMode,
        duplex: duplex ?? this.duplex,
        status: status ?? this.status,
        spoolerJobId: spoolerJobId ?? this.spoolerJobId,
        pagesPrinted: pagesPrinted ?? this.pagesPrinted,
        retryCount: retryCount ?? this.retryCount,
        startedAt: startedAt ?? this.startedAt,
        completedAt: completedAt ?? this.completedAt,
        errorMessage: errorMessage ?? this.errorMessage,
        preflightFailed: preflightFailed ?? this.preflightFailed,
        preflightMessage: preflightMessage ?? this.preflightMessage,
      );
}

/// Small extension so nullable strings can be parsed inline above.
extension _StringLet on String {
  T let<T>(T Function(String) f) => f(this);
}
