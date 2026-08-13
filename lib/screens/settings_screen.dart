import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'package:printflow/models/app_settings.dart';
import 'package:printflow/models/print_job.dart';
import 'package:printflow/models/printer_profile.dart';
import 'package:printflow/services/printer_service.dart';
import 'package:printflow/services/database_service.dart';
import 'package:printflow/state/providers.dart';
import 'package:printflow/utils/sumatra.dart';

/// Settings screen (PRD §11 screen 5, Module 9): printer defaults, poll
/// interval, timeouts, auto-skip toggle + retries, alert prefs, and a
/// "Download SumatraPDF" helper for first-run setup.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  List<PrinterProfile> _printers = [];
  bool _downloading = false;
  String? _sumatraStatus;

  @override
  void initState() {
    super.initState();
    _loadPrinters();
    _checkSumatra();
  }

  Future<void> _loadPrinters() async {
    final sumatra = ref.read(sumatraPathProvider).valueOrNull;
    final printers = await PrinterService.listPrinters(sumatraExePath: sumatra);
    if (mounted) setState(() => _printers = printers);
  }

  Future<void> _checkSumatra() async {
    final path = await SumatraResolver.resolve();
    if (mounted) {
      setState(() {
        _sumatraStatus = path == null
            ? 'Not found — click Download to fetch SumatraPDF.exe.'
            : 'Found: $path';
      });
    }
  }

  Future<void> _downloadSumatra() async {
    setState(() => _downloading = true);
    try {
      final support = await getApplicationSupportDirectory();
      final target = p.join(support.path, 'SumatraPDF.exe');
      // The portable single-exe download endpoint.
      final url = 'https://www.sumatrapdfreader.org/dl/SumatraPDF-prerel-64.exe';
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Invoke-WebRequest -Uri "$url" -OutFile "$target"',
      ]);
      if (result.exitCode == 0 && await File(target).exists()) {
        setState(() => _sumatraStatus = 'Downloaded: $target');
      } else {
        setState(() => _sumatraStatus = 'Download failed: ${result.stderr}');
      }
    } catch (e) {
      setState(() => _sumatraStatus = 'Download error: $e');
    } finally {
      setState(() => _downloading = false);
      _checkSumatra();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load settings: $e')),
        data: (s) => _body(context, s),
      ),
    );
  }

  Widget _body(BuildContext context, AppSettings s) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Print Engine (SumatraPDF)', [
          ListTile(
            leading: const Icon(Icons.print),
            title: const Text('SumatraPDF.exe'),
            subtitle: Text(_sumatraStatus ?? 'Checking…'),
            trailing: _downloading
                ? const CircularProgressIndicator(strokeWidth: 2)
                : FilledButton.tonal(
                    onPressed: _downloadSumatra,
                    child: const Text('Download'),
                  ),
          ),
        ]),
        _section('Default Printer', [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Default printer',
                border: OutlineInputBorder(),
              ),
              value: s.defaultPrinterName,
              items: _printers
                  .map((p) => DropdownMenuItem(
                        value: p.name,
                        child: Text(p.name + (p.isDefault ? '  (system default)' : '')),
                      ))
                  .toList(),
              onChanged: (v) => _save(s.copyWith(defaultPrinterName: v)),
            ),
          ),
          ListTile(
            title: const Text('Default copies'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: () => _save(s.copyWith(
                        defaultCopies: (s.defaultCopies - 1).clamp(1, 50)))),
                Text('${s.defaultCopies}'),
                IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _save(s.copyWith(
                        defaultCopies: (s.defaultCopies + 1).clamp(1, 50)))),
              ],
            ),
          ),
          ListTile(
            title: const Text('Default color mode'),
            trailing: SegmentedButton<ColorMode>(
              segments: const [
                ButtonSegment(value: ColorMode.color, label: Text('Color')),
                ButtonSegment(value: ColorMode.grayscale, label: Text('B&W')),
              ],
              selected: {s.defaultColorMode},
              onSelectionChanged: (set) =>
                  _save(s.copyWith(defaultColorMode: set.first)),
            ),
          ),
          ListTile(
            title: const Text('Default duplex'),
            trailing: DropdownButton<DuplexMode>(
              value: s.defaultDuplex,
              items: DuplexMode.values
                  .map((d) =>
                      DropdownMenuItem(value: d, child: Text(d.label)))
                  .toList(),
              onChanged: (v) => _save(s.copyWith(defaultDuplex: v)),
            ),
          ),
        ]),
        _section('Timing & Reliability', [
          _sliderTile(
            'Spooler poll interval',
            '${s.pollIntervalMs} ms',
            s.pollIntervalMs / 5000,
            (v) => _save(s.copyWith(
                pollIntervalMs: ((v * 5000).round()).clamp(500, 5000))),
          ),
          _sliderTile(
            'Stuck-job timeout',
            '${s.stuckJobTimeoutSec} s',
            s.stuckJobTimeoutSec / 600,
            (v) => _save(s.copyWith(
                stuckJobTimeoutSec: ((v * 600).round()).clamp(30, 600))),
          ),
          _sliderTile(
            'Process watchdog timeout',
            '${s.processWatchdogTimeoutSec} s',
            s.processWatchdogTimeoutSec / 300,
            (v) => _save(s.copyWith(
                processWatchdogTimeoutSec:
                    ((v * 300).round()).clamp(15, 300))),
          ),
        ]),
        _section('Unattended Runs', [
          SwitchListTile(
            title: const Text('Auto-skip after N retries'),
            subtitle: const Text(
                'Off by default — nothing should print out of order or slip '
                'past unnoticed (PRD §7).'),
            value: s.autoSkipEnabled,
            onChanged: (v) => _save(s.copyWith(autoSkipEnabled: v)),
          ),
          if (s.autoSkipEnabled)
            ListTile(
              title: const Text('Max retries before auto-skip'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: () => _save(s.copyWith(
                          autoSkipRetries:
                              (s.autoSkipRetries - 1).clamp(1, 10)))),
                  Text('${s.autoSkipRetries}'),
                  IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () => _save(s.copyWith(
                          autoSkipRetries:
                              (s.autoSkipRetries + 1).clamp(1, 10)))),
                ],
              ),
            ),
        ]),
        _section('Alerts', [
          SwitchListTile(
            title: const Text('Sound alerts on failure'),
            value: s.soundAlertsEnabled,
            onChanged: (v) => _save(s.copyWith(soundAlertsEnabled: v)),
          ),
        ]),
        const SizedBox(height: 16),
        if (!DatabaseService.isSupportedOnPlatform)
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text('Windows-only features'),
              subtitle: Text(
                  'Printing, spooler polling and SumatraPDF integration run '
                  'on Windows only. The UI still works on other platforms for '
                  'preview/development.'),
            ),
          ),
      ],
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600)),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _sliderTile(String label, String value, double normalized,
      ValueChanged<double> onChanged) {
    return ListTile(
      title: Text(label),
      subtitle: Slider(
        value: normalized.clamp(0.0, 1.0),
        onChanged: onChanged,
      ),
      trailing: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Future<void> _save(AppSettings next) async {
    await ref.read(settingsProvider.notifier).update(next);
  }
}
