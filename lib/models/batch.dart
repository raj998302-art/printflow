/// Batch-level status.
enum BatchStatus {
  draft,
  running,
  paused,
  completed,
  cancelled;

  String get label => switch (this) {
        BatchStatus.draft => 'Draft',
        BatchStatus.running => 'Running',
        BatchStatus.paused => 'Paused',
        BatchStatus.completed => 'Completed',
        BatchStatus.cancelled => 'Cancelled',
      };
}

/// A single print batch — one "Start Batch" run over an ordered list of jobs.
class Batch {
  final String id;
  final String name;
  final DateTime createdAt;
  BatchStatus status;
  int totalJobs;
  int completedJobs;
  int failedJobs;
  String? printerName;

  Batch({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.status,
    required this.totalJobs,
    required this.completedJobs,
    required this.failedJobs,
    this.printerName,
  });

  factory Batch.create({String? name, String? printerName}) {
    return Batch(
      id: _uuid(),
      name: name ?? 'Batch ${DateTime.now().toIso8601String()}',
      createdAt: DateTime.now(),
      status: BatchStatus.draft,
      totalJobs: 0,
      completedJobs: 0,
      failedJobs: 0,
      printerName: printerName,
    );
  }

  double get progress {
    if (totalJobs == 0) return 0;
    return completedJobs / totalJobs;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'totalJobs': totalJobs,
        'completedJobs': completedJobs,
        'failedJobs': failedJobs,
        'printerName': printerName,
      };

  factory Batch.fromMap(Map<String, dynamic> m) => Batch(
        id: m['id'] as String,
        name: m['name'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        status: BatchStatus.values.byName(m['status'] as String),
        totalJobs: m['totalJobs'] as int,
        completedJobs: m['completedJobs'] as int,
        failedJobs: m['failedJobs'] as int,
        printerName: m['printerName'] as String?,
      );

  Batch copyWith({
    String? name,
    BatchStatus? status,
    int? totalJobs,
    int? completedJobs,
    int? failedJobs,
    String? printerName,
  }) =>
      Batch(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        status: status ?? this.status,
        totalJobs: totalJobs ?? this.totalJobs,
        completedJobs: completedJobs ?? this.completedJobs,
        failedJobs: failedJobs ?? this.failedJobs,
        printerName: printerName ?? this.printerName,
      );
}

String _uuid() {
  // Lightweight unique id without extra deps at the model layer.
  return '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}-'
      '${(DateTime.now().hashCode & 0xffffff).toRadixString(16)}';
}
