/// App-wide settings (PRD §9 Settings model + Module 9).
class AppSettings {
  int pollIntervalMs;
  int stuckJobTimeoutSec;
  int processWatchdogTimeoutSec;
  bool autoSkipEnabled;
  int autoSkipRetries;
  bool soundAlertsEnabled;
  String? defaultPrinterName;
  int defaultCopies;
  ColorMode defaultColorMode;
  DuplexMode defaultDuplex;

  AppSettings({
    this.pollIntervalMs = 1000,
    this.stuckJobTimeoutSec = 180,
    this.processWatchdogTimeoutSec = 60,
    this.autoSkipEnabled = false,
    this.autoSkipRetries = 3,
    this.soundAlertsEnabled = true,
    this.defaultPrinterName,
    this.defaultCopies = 1,
    this.defaultColorMode = ColorMode.grayscale,
    this.defaultDuplex = DuplexMode.none,
  });

  /// Sensible defaults for an unattended-but-noticed run.
  factory AppSettings.defaults() => AppSettings();

  Map<String, dynamic> toMap() => {
        'pollIntervalMs': pollIntervalMs,
        'stuckJobTimeoutSec': stuckJobTimeoutSec,
        'processWatchdogTimeoutSec': processWatchdogTimeoutSec,
        'autoSkipEnabled': autoSkipEnabled ? 1 : 0,
        'autoSkipRetries': autoSkipRetries,
        'soundAlertsEnabled': soundAlertsEnabled ? 1 : 0,
        'defaultPrinterName': defaultPrinterName,
        'defaultCopies': defaultCopies,
        'defaultColorMode': defaultColorMode.name,
        'defaultDuplex': defaultDuplex.name,
      };

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        pollIntervalMs: m['pollIntervalMs'] as int,
        stuckJobTimeoutSec: m['stuckJobTimeoutSec'] as int,
        processWatchdogTimeoutSec: m['processWatchdogTimeoutSec'] as int,
        autoSkipEnabled: (m['autoSkipEnabled'] as int) == 1,
        autoSkipRetries: m['autoSkipRetries'] as int,
        soundAlertsEnabled: (m['soundAlertsEnabled'] as int) == 1,
        defaultPrinterName: m['defaultPrinterName'] as String?,
        defaultCopies: m['defaultCopies'] as int,
        defaultColorMode: ColorMode.values.byName(m['defaultColorMode'] as String),
        defaultDuplex: DuplexMode.values.byName(m['defaultDuplex'] as String),
      );

  AppSettings copyWith({
    int? pollIntervalMs,
    int? stuckJobTimeoutSec,
    int? processWatchdogTimeoutSec,
    bool? autoSkipEnabled,
    int? autoSkipRetries,
    bool? soundAlertsEnabled,
    String? defaultPrinterName,
    int? defaultCopies,
    ColorMode? defaultColorMode,
    DuplexMode? defaultDuplex,
  }) =>
      AppSettings(
        pollIntervalMs: pollIntervalMs ?? this.pollIntervalMs,
        stuckJobTimeoutSec: stuckJobTimeoutSec ?? this.stuckJobTimeoutSec,
        processWatchdogTimeoutSec:
            processWatchdogTimeoutSec ?? this.processWatchdogTimeoutSec,
        autoSkipEnabled: autoSkipEnabled ?? this.autoSkipEnabled,
        autoSkipRetries: autoSkipRetries ?? this.autoSkipRetries,
        soundAlertsEnabled: soundAlertsEnabled ?? this.soundAlertsEnabled,
        defaultPrinterName: defaultPrinterName ?? this.defaultPrinterName,
        defaultCopies: defaultCopies ?? this.defaultCopies,
        defaultColorMode: defaultColorMode ?? this.defaultColorMode,
        defaultDuplex: defaultDuplex ?? this.defaultDuplex,
      );
}
