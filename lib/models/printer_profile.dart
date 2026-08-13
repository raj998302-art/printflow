import 'package:printflow/models/print_job.dart';

/// A discovered Windows printer + batch-level default print options.
class PrinterProfile {
  final String name;
  bool isDefault;
  int defaultCopies;
  ColorMode defaultColorMode;
  DuplexMode defaultDuplex;

  PrinterProfile({
    required this.name,
    this.isDefault = false,
    this.defaultCopies = 1,
    this.defaultColorMode = ColorMode.grayscale,
    this.defaultDuplex = DuplexMode.none,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'isDefault': isDefault ? 1 : 0,
        'defaultCopies': defaultCopies,
        'defaultColorMode': defaultColorMode.name,
        'defaultDuplex': defaultDuplex.name,
      };

  factory PrinterProfile.fromMap(Map<String, dynamic> m) => PrinterProfile(
        name: m['name'] as String,
        isDefault: (m['isDefault'] as int) == 1,
        defaultCopies: m['defaultCopies'] as int,
        defaultColorMode: ColorMode.values.byName(m['defaultColorMode'] as String),
        defaultDuplex: DuplexMode.values.byName(m['defaultDuplex'] as String),
      );
}
