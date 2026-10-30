import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/local_store.dart';
import '../../desktop.dart';
import '../../security/app_lock.dart';
import '../../sync/lan_sync_service.dart';
import '../../theme/theme_controller.dart';
import '../../theme/tokens.dart';
import '../entry/manual_panel_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import '../tests/tests_screen.dart';
import '../records/records_screen.dart';
import 'desktop_shell.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.lock,
    required this.theme,
    required this.sync,
  });

  final LocalStore store;
  final AppLockController lock;
  final ThemeController theme;
  final LanSyncService sync;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.sync.addListener(_onSync);
  }

  @override
  void dispose() {
    widget.sync.removeListener(_onSync);
    super.dispose();
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    setState(() {});
    widget.sync.scheduleSyncSoon();
  }

  @override
  Widget build(BuildContext context) {
    BodylineColors.syncFrom(context);
    if (useWideShell(context)) {
      return DesktopShell(
          store: widget.store,
          lock: widget.lock,
          theme: widget.theme,
          sync: widget.sync);
    }

    final store = widget.store;
    // Hide FAB on Home (crowded) and Profile (has its own Add). Records uses shell Add.
    final hideFab = _tab == 0 || _tab == 3;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: IndexedStack(
        index: _tab,
        children: [
          HomeScreen(store: store, onChanged: _refresh),
          TestsScreen(store: store, onChanged: _refresh),
          RecordsScreen(
            store: store,
            onAdd: () {
              _openAdd();
            },
          ),
          ProfileScreen(
            store: store,
            onChanged: _refresh,
            lock: widget.lock,
            theme: widget.theme,
            sync: widget.sync,
          ),
        ],
      ),
      floatingActionButton: hideFab
          ? null
          : FloatingActionButton(
              heroTag: 'shell-add-report-fab',
              onPressed: _openAdd,
              tooltip: 'Add report',
              child: const Icon(Icons.add),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.science_outlined),
            selectedIcon: Icon(Icons.science),
            label: 'Tests',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualPanelScreen(
          store: widget.store,
          onSaved: () {
            _refresh();
          },
        ),
      ),
    );
    _refresh();
  }
}

/// Brand mark — heart outline + ECG (classic); wordmark is Vitalog (ADR-007).
class BodylineMark extends StatelessWidget {
  const BodylineMark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/brand/bodyline-mark.svg',
      width: size,
      height: size,
      semanticsLabel: 'Vitalog',
    );
  }
}

/// Wordmark used in headers (Fraunces · ink, per desktop mockups).
class BodylineWordmark extends StatelessWidget {
  const BodylineWordmark({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Vitalog',
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: BodylineColors.ink,
            fontSize: size,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
    );
  }
}

/// Mark + wordmark lockup used in the desktop sidebar.
class BodylineLockup extends StatelessWidget {
  const BodylineLockup({super.key, this.markSize = 32, this.wordSize = 22});
  final double markSize;
  final double wordSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BodylineMark(size: markSize),
        SizedBox(width: markSize * 0.25),
        BodylineWordmark(size: wordSize),
      ],
    );
  }
}
