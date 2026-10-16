import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../desktop.dart';
import '../../sync/lan_sync_service.dart';
import '../../sync/pair_link.dart';
import 'pair_scan_screen.dart';
import '../../theme/tokens.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.sync, this.initialHost});

  final LanSyncService sync;
  final String? initialHost;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _hostCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  var _busy = false;
  List<SyncPeer> _remotePeers = [];

  LanSyncService get sync => widget.sync;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = sync.deviceName;
    sync.addListener(_onSync);
    PairDeepLinks.pendingHost.addListener(_onPendingHost);
    sync.refreshLocalIp();
    _applyHost(widget.initialHost ?? PairDeepLinks.pendingHost.value);
  }

  void _onPendingHost() {
    _applyHost(PairDeepLinks.pendingHost.value);
  }

  void _applyHost(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    final host = PairDeepLinks.parseHost(raw) ?? raw.trim();
    _hostCtrl.text = host;
    PairDeepLinks.pendingHost.value = null;
    if (mounted) setState(() {});
  }

  void _onSync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    sync.removeListener(_onSync);
    PairDeepLinks.pendingHost.removeListener(_onPendingHost);
    _hostCtrl.dispose();
    _pinCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is StateError
                ? e.message
                : 'Sync failed. Check Wi‑Fi and try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pairFlow() async {
    final host =
        PairDeepLinks.parseHost(_hostCtrl.text.trim()) ?? _hostCtrl.text.trim();
    final pin = _pinCtrl.text.trim();
    final hello = await sync.probeHub(host: host);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect to this host?'),
        content: Text(
          '“${hello.name}” (${hello.platform})\n'
          'ID ${hello.deviceId.length > 8 ? hello.deviceId.substring(0, 8) : hello.deviceId}…\n\n'
          'Only continue if this is your device — not a neighbour on the same Wi‑Fi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: BodylineColors.ink,
              foregroundColor: BodylineColors.onInk,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final hub = await sync.pairWithHub(host: host, pin: pin);
    _pinCtrl.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Paired with ${hub.name}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shellWide = useWideShell(context);
    return Scaffold(
      backgroundColor: BodylineColors.paper,
      appBar: AppBar(
        title: const Text('Devices & sync'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: sync,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, c) {
              const gap = 20.0;
              final padH = shellWide ? 32.0 : 20.0;
              // Max 2 columns
              final cols = c.maxWidth < 780 ? 1 : 2;

              final intro = Text(
                'Same Wi‑Fi only. Turn hosting on once — it restarts with this app. '
                'Join PIN refreshes every minute; trusted devices stay paired. '
                'Vault sync uses a separate key — Vitalog never stores your data.',
                style: Theme.of(context).textTheme.bodyMedium,
              );

              final thisDevice = _section(
                context,
                null,
                _thisDeviceCard(context),
              );
              final hostCore = _section(
                context,
                'Host on this network',
                _hostCoreCard(context),
              );
              final trusted = _section(
                context,
                'Trusted devices',
                _trustedCard(context),
              );
              final join = _section(
                context,
                'Join a host',
                _joinCard(context),
              );
              final paired = _section(
                context,
                'Paired hosts (${sync.pairedHubs.length})',
                _pairedCard(context),
              );
              final extras = _extras(context);

              Widget column(List<Widget> kids) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < kids.length; i++) ...[
                        if (i > 0) const SizedBox(height: gap),
                        kids[i],
                      ],
                    ],
                  );

              late final Widget body;
              if (cols == 1) {
                body = column([
                  intro,
                  thisDevice,
                  hostCore,
                  trusted,
                  join,
                  paired,
                  if (extras.isNotEmpty) ...extras,
                ]);
              } else {
                // Left: host + QR/PIN · Right: this device, trusted, join, paired
                body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    intro,
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: column([hostCore]),
                        ),
                        const SizedBox(width: gap),
                        Expanded(
                          flex: 4,
                          child: column([
                            thisDevice,
                            trusted,
                            join,
                            paired,
                          ]),
                        ),
                      ],
                    ),
                    if (extras.isNotEmpty) ...[
                      const SizedBox(height: gap),
                      ...extras,
                    ],
                  ],
                );
              }

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padH, 12, padH, 32),
                child: body,
              );
            },
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String? title, Widget card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title, style: _h(context)),
          const SizedBox(height: 8),
        ],
        card,
      ],
    );
  }

  Widget _thisDeviceCard(BuildContext context) {
    return _card([
      ListTile(
        title: const Text('This device'),
        subtitle: Text(
          '${sync.deviceName} · ${sync.platformLabel}\n'
          'ID ${sync.deviceId.substring(0, 8)}…',
        ),
        isThreeLine: true,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await sync.setDeviceName(_nameCtrl.text);
                      }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _hostCoreCard(BuildContext context) {
    return _card([
      SwitchListTile(
        title: Text(sync.hubRunning ? 'Hosting' : 'Start as host'),
        subtitle: Text(
          sync.hubRunning
              ? 'Channel stays on; approve new devices once'
              : 'Desktop or phone can host — channel restarts next launch',
        ),
        value: sync.hubRunning,
        activeThumbColor: BodylineColors.teal,
        onChanged: _busy
            ? null
            : (on) => _run(() async {
                  if (on) {
                    await sync.startHub();
                  } else {
                    await sync.stopHub();
                  }
                }),
      ),
      if (sync.hubRunning) ...[
        const Divider(height: 1),
        ListTile(
          title: const Text('Address'),
          subtitle: Text(
            '${sync.localIp ?? '…'}:${kLanSyncPort}',
          ),
          trailing: IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: sync.localIp == null
                ? null
                : () {
                    Clipboard.setData(
                      ClipboardData(
                        text: '${sync.localIp}:${kLanSyncPort}',
                      ),
                    );
                  },
          ),
        ),
        if (sync.localIp != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                QrImageView(
                  data: PairDeepLinks.encodeHostQr(
                    sync.localIp!,
                    port: kLanSyncPort,
                  ),
                  size: 220,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(10),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Scan with Vitalog (or the phone camera) to open Join with this address. '
                    'PIN is not in the QR — enter it on the other device.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Join PIN',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sync.pairingPin,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ValueListenableBuilder<int>(
                      valueListenable: sync.pinTick,
                      builder: (context, _, __) => Text(
                        'Refreshes in ${sync.pairingPinSecondsLeft}s · trusted devices stay paired',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await sync.rotatePin();
                        }),
                child: const Text('New PIN'),
              ),
            ],
          ),
        ),
        if (sync.pendingPairs.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Waiting for your approval',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: BodylineColors.orange,
              ),
            ),
          ),
          for (final p in sync.pendingPairs)
            ListTile(
              leading: const Icon(Icons.phonelink_lock),
              title: Text(p.name),
              subtitle: Text(
                '${p.platform} · ${p.deviceId.substring(0, 8)}…'
                '${p.address != null ? ' · ${p.address}' : ''}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => sync.denyPending(p.id)),
                    child: const Text('Deny'),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => sync.approvePending(p.id)),
                    style: FilledButton.styleFrom(
                      backgroundColor: BodylineColors.teal,
                    ),
                    child: const Text('Approve'),
                  ),
                ],
              ),
            ),
        ],
      ],
    ]);
  }

  Widget _trustedCard(BuildContext context) {
    if (!sync.hubRunning) {
      return _card([
        const ListTile(
          title: Text('Start hosting to see trusted devices'),
          subtitle: Text('Approve join requests once — they stay paired.'),
        ),
      ]);
    }
    return _card([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          'Trusted devices (${sync.connectedPeers.length})',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      if (sync.connectedPeers.isEmpty)
        const ListTile(
          dense: true,
          title: Text('None yet — wait for a join request'),
        )
      else
        for (final p in sync.connectedPeers)
          ListTile(
            dense: true,
            leading: Icon(
              p.platform.contains('android') || p.platform.contains('ios')
                  ? Icons.phone_iphone
                  : Icons.computer,
            ),
            title: Text(p.name),
            subtitle: Text(
              '${p.platform} · ${p.deviceId.substring(0, 8)}…',
            ),
            trailing: IconButton(
              tooltip: 'Forget',
              icon: const Icon(Icons.link_off),
              onPressed: _busy
                  ? null
                  : () => _run(() => sync.revokePeer(p.deviceId)),
            ),
          ),
    ]);
  }

  Widget _joinCard(BuildContext context) {
    return _card([
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: TextField(
          controller: _hostCtrl,
          decoration: const InputDecoration(
            labelText: 'Host address',
            hintText: 'From host QR / copy · 192.168.1.20:17843',
            isDense: true,
          ),
          keyboardType: TextInputType.url,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: TextField(
          controller: _pinCtrl,
          decoration: const InputDecoration(
            labelText: 'PIN',
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (Platform.isAndroid || Platform.isIOS)
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        final host = await Navigator.of(context).push<String>(
                          MaterialPageRoute(
                            builder: (_) => const PairScanScreen(),
                          ),
                        );
                        if (host == null || !mounted) return;
                        _applyHost(host);
                      },
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scan host QR'),
              ),
            if (Platform.isAndroid || Platform.isIOS) const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _run(_pairFlow),
              style: FilledButton.styleFrom(
                backgroundColor: BodylineColors.ink,
                foregroundColor: BodylineColors.onInk,
              ),
              child: const Text('Pair'),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _pairedCard(BuildContext context) {
    return _card([
      if (sync.pairedHubs.isEmpty)
        const ListTile(
          title: Text('None yet'),
          subtitle: Text(
            'Pair with each desktop you use — one phone can keep several.',
          ),
        )
      else
        for (final h in sync.pairedHubs) ...[
          ListTile(
            leading: const Icon(Icons.computer),
            title: Text(h.name),
            subtitle: Text('${h.host}:${h.port}'),
            trailing: Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            final msg = await sync.syncWithHub(h);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          }),
                  child: const Text('Sync'),
                ),
                IconButton(
                  tooltip: 'Forget',
                  onPressed: _busy
                      ? null
                      : () => _run(() => sync.forgetHub(h)),
                  icon: const Icon(Icons.link_off),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      if (sync.pairedHubs.isNotEmpty)
        Padding(
          padding: const EdgeInsets.all(12),
          child: OutlinedButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                      final msg = await sync.syncAllHubs();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(msg)),
                      );
                    }),
            child: const Text('Sync all paired hosts'),
          ),
        ),
    ]);
  }


  Widget _familyScopeCard(BuildContext context) {
    final profiles = sync.store.profiles;
    final syncAs = sync.syncAsProfileId ?? sync.store.activeProfileId;
    return _card([
      const ListTile(
        title: Text('Family sync scope'),
        subtitle: Text(
          'Sync as a member · full vault or selected profiles (ADR-010)',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: DropdownButtonFormField<String?>(
          initialValue: syncAs,
          decoration: const InputDecoration(
            labelText: 'Sync as',
            isDense: true,
          ),
          items: [
            for (final p in profiles)
              DropdownMenuItem(value: p.id, child: Text(p.name)),
          ],
          onChanged: _busy
              ? null
              : (id) => _run(() async {
                    await sync.setFamilySyncPrefs(
                      syncAs: id,
                      scope: sync.syncScope,
                      profileIds: sync.syncProfileIds,
                    );
                  }),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'full', label: Text('Full')),
            ButtonSegment(value: 'partial', label: Text('Partial')),
          ],
          selected: {sync.syncScope == 'partial' ? 'partial' : 'full'},
          onSelectionChanged: _busy
              ? null
              : (s) => _run(() async {
                    final scope = s.first;
                    await sync.setFamilySyncPrefs(
                      syncAs: sync.syncAsProfileId ?? sync.store.activeProfileId,
                      scope: scope,
                      profileIds: scope == 'partial'
                          ? [
                              sync.syncAsProfileId ??
                                  sync.store.activeProfileId ??
                                  '',
                            ].where((e) => e.isNotEmpty).toList()
                          : const [],
                    );
                  }),
        ),
      ),
    ]);
  }

  List<Widget> _extras(BuildContext context) {
    final out = <Widget>[];
    out.add(_familyScopeCard(context));
    if (sync.hubRunning && sync.connectedPeers.isNotEmpty) {
      out.add(
        _card([
          const ListTile(
            title: Text('Device freshness'),
            subtitle: Text('Last successful sync per trusted device'),
          ),
          for (final p in sync.connectedPeers)
            ListTile(
              dense: true,
              title: Text(p.name),
              subtitle: Text(() {
                final at = sync.lastSyncByDevice[p.deviceId];
                if (at == null) return 'Not synced yet';
                final m = DateTime.now().difference(at).inMinutes;
                if (m < 1) return 'Just now';
                if (m < 60) return '$m min ago';
                return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
              }()),
            ),
        ]),
      );
    }
    if (sync.pairedHubs.isNotEmpty) {
      out.add(
        TextButton(
          onPressed: _busy
              ? null
              : () => _run(() async {
                    if (sync.pairedHubs.isEmpty) return;
                    _remotePeers =
                        await sync.fetchPeers(sync.pairedHubs.first);
                    setState(() {});
                  }),
          child: const Text('Refresh peers on first host'),
        ),
      );
      if (_remotePeers.isNotEmpty) {
        out.add(
          _card([
            for (final p in _remotePeers)
              ListTile(
                dense: true,
                title: Text(p.name),
                subtitle: Text(p.platform),
              ),
          ]),
        );
      }
    }
    if (sync.lastStatus != null) {
      out.add(
        Text(
          sync.lastStatus!,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    if (sync.lastError != null) {
      out.add(
        Text(
          sync.lastError!,
          style: TextStyle(color: BodylineColors.danger),
        ),
      );
    }
    return out;
  }

  TextStyle? _h(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          );

  Widget _card(List<Widget> children) {
    return Material(
      color: BodylineColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BodylineRadii.cardSmall),
        side: BorderSide(color: BodylineColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}
