import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:printflow/state/providers.dart';
import 'package:printflow/screens/home_screen.dart';
import 'package:printflow/screens/live_dashboard.dart';
import 'package:printflow/screens/history_screen.dart';
import 'package:printflow/screens/settings_screen.dart';

/// PrintFlow — Batch Print Queue Manager for ESKAY PRINTERS.
///
/// Strictly-serial PDF batch printing with real completion verification
/// (PRD §7 golden rule). Built with Flutter for Windows desktop.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: PrintFlowApp()));
}

class PrintFlowApp extends ConsumerWidget {
  const PrintFlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PrintFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC2410C),
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC2410C),
          brightness: Brightness.dark,
        ),
      ),
      home: const PrintFlowShell(),
    );
  }
}

/// Root navigation shell with a NavigationRail (desktop-appropriate).
class PrintFlowShell extends ConsumerStatefulWidget {
  const PrintFlowShell({super.key});

  @override
  ConsumerState<PrintFlowShell> createState() => _PrintFlowShellState();
}

class _PrintFlowShellState extends ConsumerState<PrintFlowShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Detect an interrupted batch on launch (Module 10 — Crash Recovery).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(batchProvider.notifier).detectInterrupted();
    });
  }

  @override
  Widget build(BuildContext context) {
    final batch = ref.watch(batchProvider);
    // While a batch is running, force the dashboard into view.
    final forceDashboard = batch.isRunning || batch.isPaused;
    final index = forceDashboard ? 2 : _index;

    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: Text('Queue'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('History'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Dashboard'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings'),
      ),
    ];

    final pages = <Widget>[
      const HomeScreen(),
      const HistoryScreen(),
      const LiveDashboard(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index.clamp(0, destinations.length - 1),
            onDestinationSelected: (i) {
              if (!forceDashboard) setState(() => _index = i);
            },
            extended: MediaQuery.of(context).size.width > 1100,
            labelType: MediaQuery.of(context).size.width > 1100
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
              child: Column(
                children: [
                  Icon(Icons.print,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 6),
                  const Text(
                    'PrintFlow',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            destinations: destinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[index.clamp(0, pages.length - 1)]),
        ],
      ),
    );
  }
}
