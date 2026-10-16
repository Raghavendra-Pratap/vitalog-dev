import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../updates/app_update.dart';

import '../../data/catalog_host.dart';
import '../../data/drug_index.dart';
import '../../data/local_store.dart';
import '../../data/recovery_backup.dart';
import 'package:file_picker/file_picker.dart';
import '../../security/app_lock.dart';
import '../../theme/theme_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/bodyline_dialog.dart';
import '../../sync/lan_sync_service.dart';
import '../sync/sync_screen.dart';
import '../presenter/presenter_setup_screen.dart';
import 'health_connect_screen.dart';
import 'help_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.store,
    required this.lock,
    required this.theme,
    required this.sync,
    this.onChanged,
    this.desktop = false,
  });

  final LocalStore store;
  final AppLockController lock;
  final ThemeController theme;
  final LanSyncService sync;
  final VoidCallback? onChanged;
  final bool desktop;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LocalStore get store => widget.store;
  AppLockController get lock => widget.lock;
  final _recovery = RecoveryBackup();
  bool _hasRecovery = false;
  bool _canCopyRecovery = false;
  LastBackupInfo? _lastBackup;
  String _medicineLibStatus = 'Loading…';
  bool _medicineLibUpdating = false;
  String _catalogStatus = 'Loading…';
  bool _catalogUpdating = false;
  String _appUpdateStatus = 'This copy is $vitalogReleaseVersion.';
  bool _appUpdateChecking = false;
  Uri? _appUpdateUrl;

  @override
  void initState() {
    super.initState();
    _refreshBioAvailability();
    _refreshMedicineLibraryStatus();
    _refreshCatalogStatus();
    _loadBackupMeta();
    if (widget.desktop) _checkAppUpdate();
  }

  Future<void> _loadBackupMeta() async {
    final has = await _recovery.hasRecoveryKey();
    final stored = await _recovery.storedRecoveryKey();
    final last = await _recovery.lastBackup();
    if (!mounted) return;
    setState(() {
      _hasRecovery = has;
      _canCopyRecovery = stored != null;
      _lastBackup = last;
    });
  }

  Future<void> _copyRecoveryKey() async {
    final key = await _recovery.storedRecoveryKey();
    if (!mounted || key == null || key.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: key));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied.')),
    );
  }

  Widget _lastBackupRow(BuildContext context) {
    final backup = _lastBackup;
    if (backup == null) return const SizedBox.shrink();
    final when = DateFormat('d MMM yyyy, h:mm a').format(backup.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  backup.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                Text(when, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (_canCopyRecovery)
            IconButton(
              tooltip: 'Copy recovery key',
              onPressed: _copyRecoveryKey,
              icon: Icon(Icons.copy_outlined, color: BodylineColors.inkMuted),
            ),
        ],
      ),
    );
  }

  Future<void> _checkAppUpdate() async {
    if (_appUpdateChecking) return;
    setState(() => _appUpdateChecking = true);
    final status = await checkAppUpdate();
    if (!mounted) return;
    setState(() {
      _appUpdateChecking = false;
      _appUpdateStatus = status.message;
      _appUpdateUrl = status.download;
    });
  }

  Future<void> _downloadAppUpdate() async {
    final url = _appUpdateUrl;
    if (url == null) {
      await _checkAppUpdate();
      return;
    }
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the download. Try again.')),
      );
    }
  }

  Future<void> _refreshMedicineLibraryStatus() async {
    final line = await DrugIndex.instance.statusLine();
    if (mounted) setState(() => _medicineLibStatus = line);
  }

  Future<void> _updateMedicineLibrary() async {
    if (_medicineLibUpdating) return;
    setState(() => _medicineLibUpdating = true);
    try {
      final result = await DrugIndex.instance.updateFromHost();
      if (!mounted) return;
      await _refreshMedicineLibraryStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the medicine library. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _medicineLibUpdating = false);
    }
  }

  Future<void> _refreshCatalogStatus() async {
    final line = await CatalogHost.instance.statusLine();
    if (mounted) setState(() => _catalogStatus = line);
  }

  Future<void> _updateCatalog() async {
    if (_catalogUpdating) return;
    setState(() => _catalogUpdating = true);
    try {
      final result = await store.updateCatalogFromHost();
      if (!mounted) return;
      await _refreshCatalogStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
      if (result.updated) widget.onChanged?.call();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the catalogue. Try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _catalogUpdating = false);
    }
  }

  Future<void> _refreshBioAvailability() async {
    await lock.refreshBiometricAvailability();
    if (mounted) setState(() {});
  }

  Future<void> _runSetting(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Could not save that setting. Try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.fromLTRB(
      widget.desktop ? 32 : 20,
      widget.desktop ? 8 : 8,
      widget.desktop ? 32 : 20,
      widget.desktop ? 28 : 32,
    );
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return Scaffold(
      appBar: (!widget.desktop || canPop)
          ? AppBar(title: const Text('Settings'))
          : null,
      backgroundColor: BodylineColors.paper,
      body: ListenableBuilder(
        listenable: lock,
        builder: (context, _) {
          final children = <Widget>[
            if (!widget.desktop) ...[
              Text(
                'Your data lives on this device. We never see it.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
            ],
            if (widget.desktop)
              _desktopGrid(context)
            else ...[
          _heading(context, 'Security'),
          _card([
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: const Text('App lock'),
              subtitle: Text(
                lock.enabled
                    ? 'PIN required when opening the app'
                    : 'Off — anyone with this device can open Vitalog',
              ),
              value: lock.enabled,
              activeThumbColor: BodylineColors.teal,
              onChanged: (on) async {
                if (on) {
                  await _setupPin();
                } else {
                  await _runSetting(lock.disable);
                }
              },
            ),
            if (lock.biometricAvailable) ...[
              Divider(height: 1, color: BodylineColors.divider),
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                title: const Text('Biometric unlock'),
                subtitle: Text(
                  lock.enabled
                      ? 'Face / fingerprint — PIN still works as backup'
                      : 'Turn on App lock first',
                ),
                value: lock.biometricEnabled,
                activeThumbColor: BodylineColors.teal,
                onChanged: !lock.enabled
                    ? null
                    : (on) => _runSetting(() => lock.setBiometric(on)),
              ),
            ],
            Divider(height: 1, color: BodylineColors.divider),
            SwitchListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: const Text('Privacy screen'),
              subtitle: const Text('Hide content in the app switcher'),
              value: lock.privacyScreen,
              activeThumbColor: BodylineColors.teal,
              onChanged: (on) => _runSetting(() => lock.setPrivacyScreen(on)),
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _infoRow(
              context,
              title: 'Database encryption',
              subtitle: 'SQLCipher on · key in device secure storage',
            ),
          ]),
          const SizedBox(height: 20),
          _heading(context, 'Appearance'),
          _card([
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: const Text('Theme'),
              subtitle: Text(_themeLabel(widget.theme.mode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTheme,
            ),
          ]),
          const SizedBox(height: 20),
          _heading(context, 'Sync & backup'),
          _card([
            _tapRow(
              context,
              title: 'Devices & Wi‑Fi sync',
              subtitle: 'Auto-sync on Wi‑Fi after pairing · tap Sync anytime',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SyncScreen(sync: widget.sync),
                  ),
                );
              },
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Present to doctor',
              subtitle: 'Filtered on-device view — nothing is sent',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PresenterSetupScreen(store: store),
                  ),
                );
              },
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _infoRow(
              context,
              title: 'Cloud sync',
              subtitle:
                  'No Vitalog server. LAN sync is available above; Drive mailbox is later.',
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: _hasRecovery ? 'Recovery key set' : 'Create recovery key',
              subtitle: _hasRecovery
                  ? 'Needed to open encrypted backups on a new device'
                  : 'Generate a one-time key — store it offline',
              onTap: _createRecoveryKey,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Encrypted backup (.blbak)',
              subtitle: 'JSON sealed with your recovery key',
              onTap: _encryptedBackup,
            ),
            if (_lastBackup != null) ...[
              Divider(height: 1, color: BodylineColors.divider),
              _lastBackupRow(context),
            ],
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Restore from .blbak',
              subtitle: 'Replaces all data on this device',
              onTap: _restoreBackup,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Export all data (JSON)',
              subtitle: 'Unencrypted archive for your files',
              onTap: () => _export(json: true),
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Export observations CSV',
              subtitle: 'Spreadsheet of lab values for this device',
              onTap: () => _export(json: false),
            ),
          ]),
          const SizedBox(height: 20),
          _heading(context, 'App'),
          _card([
            _infoRow(
              context,
              title: 'Tests catalogue',
              subtitle: _catalogStatus,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: _catalogUpdating
                  ? 'Updating catalogue…'
                  : 'Update catalogue',
              subtitle:
                  'Panels and aliases from vitalog.cc — not medical advice',
              onTap: _catalogUpdating ? () {} : _updateCatalog,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _infoRow(
              context,
              title: 'Medicine library',
              subtitle: _medicineLibStatus,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: _medicineLibUpdating
                  ? 'Updating medicine library…'
                  : 'Update medicine library',
              subtitle:
                  'Name suggestions from vitalog.cc — not advice or diagnosis',
              onTap: _medicineLibUpdating ? () {} : _updateMedicineLibrary,
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Health Connect / HealthKit',
              subtitle: 'Opt-in weight, glucose, blood pressure on this device',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HealthConnectScreen(
                      store: store,
                      onChanged: widget.onChanged,
                    ),
                  ),
                );
              },
            ),
            Divider(height: 1, color: BodylineColors.divider),
            _tapRow(
              context,
              title: 'Help',
              subtitle: 'Message BSOC about Vitalog or closed testing',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HelpScreen()),
                );
              },
            ),
          ]),
          const SizedBox(height: 20),
          _heading(context, 'Danger zone'),
          Material(
            color: BodylineColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              side: BorderSide(color: BodylineColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
              onTap: _confirmDelete,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete all data',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.danger,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${store.profiles.length} profiles · ${store.observations.length} values · encrypted files',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
            ],
          ];
          if (widget.desktop) {
            return SingleChildScrollView(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            );
          }
          return ListView(padding: pad, children: children);
        },
      ),
    );
  }


  Widget _desktopGrid(BuildContext context) {
    final lock = this.lock;
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 20.0;
        const minCol = 360.0;
        final twoCol = c.maxWidth >= (minCol * 2 + gap);

        Widget section(String title, List<Widget> rows) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 10),
                _card(rows),
              ],
            );

        final copy = section('This copy', [
          _actionRow(
            icon: Icons.system_update_alt_outlined,
            title: 'Vitalog $vitalogReleaseVersion',
            subtitle: _appUpdateChecking ? 'Checking GitHub…' : _appUpdateStatus,
            actionLabel: _appUpdateUrl != null ? 'Download' : 'Check',
            onAction: _appUpdateChecking
                ? () {}
                : () {
                    if (_appUpdateUrl != null) {
                      _downloadAppUpdate();
                    } else {
                      _checkAppUpdate();
                    }
                  },
          ),
        ]);

        final sync = section('Sync & backup', [
          _actionRow(
            icon: Icons.cloud_outlined,
            title: 'Encrypted backup',
            subtitle: 'Save a sealed .blbak to your own Drive or iCloud',
            actionLabel: 'Backup',
            onAction: _encryptedBackup,
          ),
          if (_lastBackup != null) ...[
            Divider(height: 1, color: BodylineColors.divider),
            _lastBackupRow(context),
          ],
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.devices_outlined,
            title: 'Devices & Wi‑Fi sync',
            subtitle: 'Host stays on · phones sync automatically when paired',
            actionLabel: 'Open',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SyncScreen(sync: widget.sync),
                ),
              );
            },
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.present_to_all_outlined,
            title: 'Present to doctor',
            subtitle: 'Filtered clinic view on this screen',
            actionLabel: 'Present',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PresenterSetupScreen(store: store),
                ),
              );
            },
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.download_outlined,
            title: 'Export all data',
            subtitle: 'Encrypted archive or readable CSV + JSON',
            actionLabel: 'Export',
            onAction: () => _export(json: true),
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.upload_outlined,
            title: 'Restore from .blbak',
            subtitle: 'Replaces all data on this device',
            actionLabel: 'Restore',
            onAction: _restoreBackup,
          ),
        ]);

        final security = section('Security', [
          _actionRow(
            icon: Icons.vpn_key_outlined,
            title: 'Recovery key',
            subtitle: _hasRecovery
                ? 'Needed to restore on a new device. Keep it offline.'
                : 'Generate a one-time key — store it offline',
            actionLabel: _hasRecovery ? 'View / print' : 'Create',
            onAction: _createRecoveryKey,
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _toggleRow(
            icon: Icons.lock_outline,
            title: 'App lock',
            subtitle: 'Ask for PIN or biometrics on open',
            value: lock.enabled,
            onChanged: (on) async {
              if (on) {
                await _setupPin();
              } else {
                await _runSetting(lock.disable);
              }
            },
          ),
          if (lock.biometricAvailable) ...[
            Divider(height: 1, color: BodylineColors.divider),
            _toggleRow(
              icon: Icons.fingerprint,
              title: 'Biometric unlock',
              subtitle: lock.enabled
                  ? 'Touch ID / fingerprint — PIN remains the backup'
                  : 'Turn on App lock first',
              value: lock.biometricEnabled,
              onChanged: !lock.enabled
                  ? null
                  : (on) => _runSetting(() => lock.setBiometric(on)),
            ),
          ],
          Divider(height: 1, color: BodylineColors.divider),
          _toggleRow(
            icon: Icons.visibility_off_outlined,
            title: 'Privacy screen',
            subtitle: 'Hide content in screenshots and app switcher',
            value: lock.privacyScreen,
            onChanged: (on) =>
                _runSetting(() => lock.setPrivacyScreen(on)),
          ),
        ]);

        final appearance = section('Appearance', [
          _actionRow(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: _themeLabel(widget.theme.mode),
            actionLabel: 'Change',
            onAction: _pickTheme,
          ),
        ]);

        final tests = section('Tests catalogue', [
          _actionRow(
            icon: Icons.show_chart_outlined,
            title: 'Catalogue version',
            subtitle: _catalogStatus,
            actionLabel: _catalogUpdating ? 'Updating…' : 'Update',
            onAction: _catalogUpdating ? () {} : _updateCatalog,
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.medication_outlined,
            title: 'Medicine library',
            subtitle: _medicineLibStatus,
            actionLabel: _medicineLibUpdating ? 'Updating…' : 'Update',
            onAction: _medicineLibUpdating ? () {} : _updateMedicineLibrary,
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.monitor_heart_outlined,
            title: 'Health Connect / HealthKit',
            subtitle:
                'Opt-in weight, glucose, blood pressure — phone only',
            actionLabel: 'Open',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => HealthConnectScreen(
                    store: store,
                    onChanged: widget.onChanged,
                  ),
                ),
              );
            },
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.support_agent_outlined,
            title: 'Help',
            subtitle: 'Message BSOC about Vitalog or closed testing',
            actionLabel: 'Open',
            onAction: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpScreen()),
              );
            },
          ),
          Divider(height: 1, color: BodylineColors.divider),
          _actionRow(
            icon: Icons.tune_outlined,
            title: 'Custom parameters',
            subtitle: 'Aliases you add stay on this device',
            actionLabel: 'Manage',
            onAction: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content:
                      Text('Custom parameters arrive with catalogue v1.1.'),
                ),
              );
            },
          ),
        ]);

        final danger = section('Danger zone', [
          _actionRow(
            icon: Icons.delete_outline,
            title: 'Delete all data',
            subtitle:
                'Removes everything from this device and your backups you choose to erase',
            actionLabel: 'Delete…',
            onAction: _confirmDelete,
            danger: true,
          ),
        ]);

        if (!twoCol) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              copy,
              SizedBox(height: gap),
              sync,
              SizedBox(height: gap),
              security,
              SizedBox(height: gap),
              appearance,
              SizedBox(height: gap),
              tests,
              SizedBox(height: gap),
              danger,
            ],
          );
        }

        // Two columns: Sync + Tests | Security + Appearance + Danger
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  SizedBox(height: gap),
                  sync,
                  SizedBox(height: gap),
                  tests,
                ],
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  security,
                  SizedBox(height: gap),
                  appearance,
                  SizedBox(height: gap),
                  danger,
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
    bool danger = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: BodylineColors.iconWell,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 20,
                color: danger ? BodylineColors.danger : BodylineColors.inkMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: danger ? BodylineColors.danger : BodylineColors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onAction,
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  danger ? BodylineColors.danger : BodylineColors.ink,
              side: BorderSide(
                color: danger ? BodylineColors.danger : BodylineColors.border,
              ),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: const StadiumBorder(),
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: BodylineColors.iconWell,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: BodylineColors.inkMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: BodylineColors.ink)),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeThumbColor: BodylineColors.teal,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _heading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: BodylineColors.surface,
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        border: Border.all(color: BodylineColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _infoRow(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: BodylineColors.ink,
            ),
          ),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _tapRow(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: BodylineColors.inkSubtle),
          ],
        ),
      ),
    );
  }


  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  Future<void> _pickTheme() async {
    final next = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final opt in [
            (ThemeMode.system, 'System', 'Follow the device setting'),
            (ThemeMode.light, 'Light', 'Always use light appearance'),
            (ThemeMode.dark, 'Dark', 'Always use dark appearance'),
          ])
            RadioListTile<ThemeMode>(
              value: opt.$1,
              groupValue: widget.theme.mode,
              title: Text(opt.$2),
              subtitle: Text(opt.$3),
              activeColor: BodylineColors.teal,
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (next != null) {
      await widget.theme.setMode(next);
      if (mounted) setState(() {});
    }
  }

  Future<void> _setupPin() async {
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showBodylineDialog<bool>(
      context: context,
      title: 'Set a PIN',
      subtitle: 'Asked when you open Vitalog on this device.',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'PIN (4–8 digits)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirm,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            decoration: const InputDecoration(
              labelText: 'Confirm PIN',
              counterText: '',
            ),
          ),
        ],
      ),
      actionsBuilder: (ctx) => [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(foregroundColor: BodylineColors.tealDark),
          child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: BodylineColors.ink,
            foregroundColor: BodylineColors.onInk,
            shape: const StadiumBorder(),
          ),
          child: const Text('Enable', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    );
    if (ok != true) {
      setState(() {});
      return;
    }
    final a = pin.text.trim();
    final b = confirm.text.trim();
    if (a.length < 4 || a != b) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PINs must match and be at least 4 digits.')),
        );
      }
      setState(() {});
      return;
    }
    await _runSetting(() => lock.setPin(a));
  }

  Future<void> _export({required bool json}) async {
    try {
      final file = json
          ? await store.exportJsonArchive()
          : await store.exportObservationsCsv();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: json ? 'Vitalog export' : 'Vitalog observations',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export failed. Try again.')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'Removes profiles, lab values, visits, reminders, and encrypted report files on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;

    final second = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm again'),
        content: const Text(
          'This is permanent. Tap Delete forever only if you are sure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (second != true) return;
    await store.wipeEverything();
    widget.onChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All local data deleted.')),
      );
      if (!widget.desktop && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _createRecoveryKey() async {
    final key = await _recovery.createRecoveryKey();
    if (!mounted) return;
    setState(() => _hasRecovery = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var copied = false;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Store this recovery key'),
            content: SelectableText(
              key,
              style: const TextStyle(
                fontFamily: 'Menlo',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: key));
                  setLocal(() => copied = true);
                },
                child: Text(copied ? 'Copied' : 'Copy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('I wrote it down'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _encryptedBackup() async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recovery key'),
        content: TextField(
          controller: pin,
          decoration: const InputDecoration(labelText: 'Enter recovery key'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create backup'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final key = pin.text.trim();
    final valid = await _recovery.verifyRecoveryKey(key);
    if (!valid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery key does not match.')),
      );
      return;
    }
    final jsonFile = await store.exportJsonArchive();
    final json = await jsonFile.readAsString();
    final bak = await _recovery.wrapExportJson(json, key);
    final kept = await _recovery.retainBackup(bak, recoveryKey: key);
    if (!mounted) return;
    await _loadBackupMeta();
    if (!mounted) return;
    await Share.shareXFiles(
      [XFile(kept.path)],
      subject: 'Vitalog encrypted backup',
    );
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    late final String raw;
    if (f.bytes != null) {
      raw = String.fromCharCodes(f.bytes!);
    } else if (f.path != null) {
      raw = await File(f.path!).readAsString();
    } else {
      return;
    }
    final keyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This replaces all health data on this device.'),
            TextField(
              controller: keyCtrl,
              decoration: const InputDecoration(labelText: 'Recovery key'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final json = await _recovery.unwrapExportJson(raw, keyCtrl.text.trim());
      await store.importFromExportJson(json);
      widget.onChanged?.call();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final nav = Navigator.of(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Backup restored on this device.')),
      );
      nav.pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not restore — check the key and file.'),
        ),
      );
    }
  }
}
