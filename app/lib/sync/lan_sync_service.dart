import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../data/local_store.dart';
import '../data/models.dart';
import '../notifications/reminder_notifications.dart';

const kLanSyncPort = 17843;

/// Join PIN refreshes this often while hosting (vault key stays stable).
const kPairingPinRotateSeconds = 60;

class SyncPeer {
  SyncPeer({
    required this.deviceId,
    required this.name,
    required this.platform,
    this.lastSeen,
    this.address,
  });

  final String deviceId;
  final String name;
  final String platform;
  final DateTime? lastSeen;
  final String? address;
}

class PairedHub {
  PairedHub({
    required this.deviceId,
    required this.name,
    required this.host,
    required this.port,
    required this.token,
    required this.pin,
  });

  final String deviceId;
  final String name;
  final String host;
  final int port;
  final String token;
  final String pin;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'name': name,
        'host': host,
        'port': port,
        'token': token,
        'pin': pin,
      };

  static PairedHub fromJson(Map<String, dynamic> m) => PairedHub(
        deviceId: m['deviceId'] as String,
        name: m['name'] as String? ?? 'Desktop',
        host: m['host'] as String,
        port: (m['port'] as num?)?.toInt() ?? kLanSyncPort,
        token: m['token'] as String,
        pin: m['pin'] as String? ?? '',
      );
}

class PendingPairRequest {
  PendingPairRequest({
    required this.id,
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.createdAt,
    this.address,
  });

  final String id;
  final String deviceId;
  final String name;
  final String platform;
  final DateTime createdAt;
  final String? address;
}

class HubHello {
  HubHello({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.port,
  });

  final String deviceId;
  final String name;
  final String platform;
  final int port;
}

/// Same-Wi‑Fi hub + multi-hub client (ADR-008).
class LanSyncService extends ChangeNotifier {
  LanSyncService(this.store);

  final LocalStore store;
  final _uuid = const Uuid();

  String deviceId = '';
  String deviceName = 'Vitalog';
  String platformLabel = 'device';
  String? localIp;
  String pairingPin = '';
  /// Hub: deviceId → last successful vault merge/pull.
  final Map<String, DateTime> lastSyncByDevice = {};
  /// ADR-010: which profile this device syncs as (null = active profile).
  String? syncAsProfileId;
  /// full | partial
  String syncScope = 'full';
  List<String> syncProfileIds = [];
  /// Stable secret for vault seal/open — not shown; does not rotate with join PIN.
  String vaultSecret = '';
  DateTime? pairingPinAt;
  bool hubRunning = false;
  String? lastError;
  String? lastStatus;

  final List<SyncPeer> connectedPeers = [];
  final List<PairedHub> pairedHubs = [];
  final List<PendingPairRequest> pendingPairs = [];

  HttpServer? _server;
  final Map<String, SyncPeer> _sessions = {}; // token → peer
  final Map<String, PendingPairRequest> _pendingById = {};
  final Map<String, String> _pendingOutcome = {}; // requestId → token | denied
  final Map<String, _PinAttemptBucket> _pinAttempts = {};
  Timer? _autoTimer;
  Timer? _debounceTimer;
  Timer? _pinRotateTimer;
  Timer? _pinTickTimer;
  bool _syncBusy = false;
  DateTime? _lastAutoSyncAt;

  int get pairingPinSecondsLeft {
    final at = pairingPinAt;
    if (at == null) return kPairingPinRotateSeconds;
    final left =
        kPairingPinRotateSeconds - DateTime.now().difference(at).inSeconds;
    return left < 0 ? 0 : left;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString('lan_device_id') ?? _uuid.v4();
    await prefs.setString('lan_device_id', deviceId);
    deviceName = prefs.getString('lan_device_name') ??
        (Platform.isMacOS
            ? 'Mac'
            : Platform.isWindows
                ? 'Windows'
                : Platform.isLinux
                    ? 'Linux'
                    : 'Phone');
    platformLabel = Platform.operatingSystem;
    final raw = prefs.getString('lan_paired_hubs');
    pairedHubs
      ..clear()
      ..addAll([
        if (raw != null)
          for (final e in (jsonDecode(raw) as List))
            PairedHub.fromJson(Map<String, dynamic>.from(e as Map)),
      ]);
    pairingPin = prefs.getString('lan_pairing_pin') ?? '';
    vaultSecret = prefs.getString('lan_vault_secret') ?? '';
    syncAsProfileId = prefs.getString('lan_sync_as_profile');
    syncScope = prefs.getString('lan_sync_scope') ?? 'full';
    syncProfileIds = prefs.getStringList('lan_sync_profile_ids') ?? [];
    await _loadSessions(prefs);
    await refreshLocalIp();
    await _ensurePin(persist: true);
    await _ensureVaultSecret(persist: true);
    pairingPinAt ??= DateTime.now();
    final preferHub = prefs.getBool('lan_prefer_hub') ?? false;
    if (preferHub) {
      unawaited(startHub());
    }
    startAutoSync();
    notifyListeners();
  }

  Future<void> _ensurePin({bool persist = false}) async {
    if (pairingPin.length == 6) {
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lan_pairing_pin', pairingPin);
      }
      pairingPinAt ??= DateTime.now();
      return;
    }
    final r = Random.secure();
    pairingPin = List.generate(6, (_) => r.nextInt(10)).join();
    pairingPinAt = DateTime.now();
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lan_pairing_pin', pairingPin);
    }
  }

  Future<void> _ensureVaultSecret({bool persist = false}) async {
    if (vaultSecret.length >= 16) {
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lan_vault_secret', vaultSecret);
      }
      return;
    }
    // Migrate: keep existing peers working — vault key was the join PIN.
    if (pairingPin.length == 6) {
      vaultSecret = pairingPin;
    } else {
      final r = Random.secure();
      vaultSecret = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
    }
    if (persist) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lan_vault_secret', vaultSecret);
    }
  }

  Future<void> setFamilySyncPrefs({
    String? syncAs,
    String scope = 'full',
    List<String> profileIds = const [],
  }) async {
    syncAsProfileId = syncAs;
    syncScope = scope;
    syncProfileIds = profileIds;
    final prefs = await SharedPreferences.getInstance();
    if (syncAs == null) {
      await prefs.remove('lan_sync_as_profile');
    } else {
      await prefs.setString('lan_sync_as_profile', syncAs);
    }
    await prefs.setString('lan_sync_scope', scope);
    await prefs.setStringList('lan_sync_profile_ids', profileIds);
    notifyListeners();
  }

  /// Rotate join PIN only — trusted devices keep syncing (vault key unchanged).
  Future<void> refreshPairingPin({bool fromTimer = false}) async {
    pairingPin = '';
    await _ensurePin(persist: true);
    if (!fromTimer) {
      lastStatus = 'Join PIN refreshed — trusted devices stay paired';
    }
    notifyListeners();
  }

  void _startPinRotation() {
    _pinRotateTimer?.cancel();
    _pinTickTimer?.cancel();
    _pinRotateTimer = Timer.periodic(
      const Duration(seconds: kPairingPinRotateSeconds),
      (_) {
        if (!hubRunning) return;
        unawaited(refreshPairingPin(fromTimer: true));
      },
    );
    // UI countdown tick
    _pinTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!hubRunning) return;
      notifyListeners();
    });
  }

  void _stopPinRotation() {
    _pinRotateTimer?.cancel();
    _pinRotateTimer = null;
    _pinTickTimer?.cancel();
    _pinTickTimer = null;
  }

  Future<void> _loadSessions(SharedPreferences prefs) async {
    _sessions.clear();
    final raw = prefs.getString('lan_hub_sessions');
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        final m = Map<String, dynamic>.from(e as Map);
        final token = m['token'] as String?;
        final peerId = m['deviceId'] as String?;
        if (token == null || peerId == null) continue;
        _sessions[token] = SyncPeer(
          deviceId: peerId,
          name: m['name'] as String? ?? 'Device',
          platform: m['platform'] as String? ?? 'device',
          lastSeen: DateTime.tryParse(m['lastSeen'] as String? ?? ''),
        );
      }
    } catch (_) {}
    _refreshPeerList();
  }

  Future<void> _persistSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lan_hub_sessions',
      jsonEncode([
        for (final e in _sessions.entries)
          {
            'token': e.key,
            'deviceId': e.value.deviceId,
            'name': e.value.name,
            'platform': e.value.platform,
            'lastSeen': e.value.lastSeen?.toIso8601String(),
          },
      ]),
    );
  }

  Future<void> setDeviceName(String name) async {
    deviceName = name.trim().isEmpty ? deviceName : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lan_device_name', deviceName);
    notifyListeners();
  }

  /// Manual join-PIN refresh. Vault key stays; trusted devices stay paired.
  Future<void> rotatePin() async {
    await refreshPairingPin();
  }

  Future<void> refreshLocalIp() async {
    try {
      localIp = await NetworkInfo().getWifiIP();
    } catch (_) {
      localIp = null;
    }
    localIp ??= await _fallbackIp();
    notifyListeners();
  }

  Future<String?> _fallbackIp() async {
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _persistHubs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lan_paired_hubs',
      jsonEncode([for (final h in pairedHubs) h.toJson()]),
    );
  }

  String? _clientKey(Request req) {
    return req.headers['x-forwarded-for']?.split(',').first.trim() ??
        req.headers['x-real-ip'] ??
        req.requestedUri.host;
  }

  bool _pinRateLimited(String key) {
    final bucket = _pinAttempts[key];
    if (bucket == null) return false;
    if (bucket.lockedUntil != null &&
        DateTime.now().isBefore(bucket.lockedUntil!)) {
      return true;
    }
    return false;
  }

  void _noteBadPin(String key) {
    final bucket = _pinAttempts.putIfAbsent(key, _PinAttemptBucket.new);
    bucket.failures += 1;
    bucket.lastAt = DateTime.now();
    if (bucket.failures >= 5) {
      bucket.lockedUntil = DateTime.now().add(const Duration(seconds: 60));
      bucket.failures = 0;
    }
  }

  void _noteGoodPin(String key) {
    _pinAttempts.remove(key);
  }

  // --- Hub ---

  Future<void> startHub() async {
    lastError = null;
    await refreshLocalIp();
    await _ensurePin(persist: true);
    await _ensureVaultSecret(persist: true);
    if (_server != null) {
      hubRunning = true;
      _startPinRotation();
      notifyListeners();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await _loadSessions(prefs);

    final app = Router();
    app.get('/v1/hello', (Request req) {
      return Response.ok(
        jsonEncode({
          'deviceId': deviceId,
          'name': deviceName,
          'platform': platformLabel,
          'port': kLanSyncPort,
          'hub': true,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    app.post('/v1/pair', (Request req) async {
      final key = _clientKey(req) ?? 'unknown';
      if (_pinRateLimited(key)) {
        return Response(
          429,
          body: jsonEncode({'error': 'rate_limited'}),
          headers: {'content-type': 'application/json'},
        );
      }
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final pin = '${body['pin'] ?? ''}';
      if (pin != pairingPin) {
        _noteBadPin(key);
        return Response.forbidden(jsonEncode({'error': 'bad_pin'}));
      }
      _noteGoodPin(key);

      final peerId = '${body['deviceId'] ?? _uuid.v4()}';
      final peerName = '${body['name'] ?? 'Device'}';
      final peerPlatform = '${body['platform'] ?? 'device'}';
      final address = key;

      // Already approved — reissue token without asking again.
      final existing = _sessions.entries
          .where((e) => e.value.deviceId == peerId)
          .toList();
      if (existing.isNotEmpty) {
        for (final e in existing) {
          _sessions.remove(e.key);
        }
        final token = _uuid.v4();
        _sessions[token] = SyncPeer(
          deviceId: peerId,
          name: peerName,
          platform: peerPlatform,
          lastSeen: DateTime.now(),
          address: address,
        );
        await _persistSessions();
        _refreshPeerList();
        return Response.ok(
          jsonEncode({
            'status': 'approved',
            'token': token,
            'deviceId': deviceId,
            'name': deviceName,
            'platform': platformLabel,
            'vaultKey': vaultSecret,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Drop stale pending for same device.
      _pendingById.removeWhere((_, p) => p.deviceId == peerId);
      pendingPairs.removeWhere((p) => p.deviceId == peerId);

      final requestId = _uuid.v4();
      final pending = PendingPairRequest(
        id: requestId,
        deviceId: peerId,
        name: peerName,
        platform: peerPlatform,
        createdAt: DateTime.now(),
        address: address,
      );
      _pendingById[requestId] = pending;
      pendingPairs.add(pending);
      lastStatus = 'Approve “$peerName” to allow sync';
      notifyListeners();

      return Response(
        202,
        body: jsonEncode({
          'status': 'pending',
          'requestId': requestId,
          'hubName': deviceName,
          'hubDeviceId': deviceId,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    app.get('/v1/pair/status', (Request req) {
      final requestId = req.requestedUri.queryParameters['requestId'] ?? '';
      if (requestId.isEmpty) {
        return Response.badRequest(body: 'requestId');
      }
      final outcome = _pendingOutcome[requestId];
      if (outcome == 'denied') {
        return Response.ok(
          jsonEncode({'status': 'denied'}),
          headers: {'content-type': 'application/json'},
        );
      }
      if (outcome != null && outcome != 'denied') {
        return Response.ok(
          jsonEncode({
            'status': 'approved',
            'token': outcome,
            'deviceId': deviceId,
            'name': deviceName,
            'platform': platformLabel,
            'vaultKey': vaultSecret,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      if (_pendingById.containsKey(requestId)) {
        return Response.ok(
          jsonEncode({
            'status': 'pending',
            'hubName': deviceName,
          }),
          headers: {'content-type': 'application/json'},
        );
      }
      return Response.notFound(jsonEncode({'error': 'unknown'}));
    });

    app.get('/v1/peers', (Request req) {
      final token = req.headers['x-vitalog-token'];
      if (token == null || !_sessions.containsKey(token)) {
        return Response.forbidden('auth');
      }
      _touch(token);
      return Response.ok(
        jsonEncode({
          'hub': {
            'deviceId': deviceId,
            'name': deviceName,
            'platform': platformLabel,
          },
          'peers': [
            for (final p in _sessions.values)
              {
                'deviceId': p.deviceId,
                'name': p.name,
                'platform': p.platform,
                'lastSeen': p.lastSeen?.toIso8601String(),
              },
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    app.get('/v1/vault', (Request req) async {
      final token = req.headers['x-vitalog-token'];
      if (token == null || !_sessions.containsKey(token)) {
        return Response.forbidden('auth');
      }
      _touch(token);
      final plain = jsonEncode(await store.exportVaultMap());
      final sealed = await _seal(plain, vaultSecret);
      return Response.ok(
        jsonEncode(sealed),
        headers: {'content-type': 'application/json'},
      );
    });

    app.post('/v1/vault', (Request req) async {
      final token = req.headers['x-vitalog-token'];
      if (token == null || !_sessions.containsKey(token)) {
        return Response.forbidden('auth');
      }
      _touch(token);
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final plain = await _open(body, vaultSecret);
      final result = await store.mergeFromExportJson(plain);
      final peer = _sessions[token];
      if (peer != null) {
        lastSyncByDevice[peer.deviceId] = DateTime.now();
      }
      lastStatus =
          'Merged from ${peer?.name ?? 'peer'}: ${result.reportsAdded} reports, ${result.careRowsAdded} care rows';
      notifyListeners();
      return Response.ok(
        jsonEncode({
          'ok': true,
          'profilesAdded': result.profilesAdded,
          'reportsAdded': result.reportsAdded,
          'careRowsAdded': result.careRowsAdded,
        }),
        headers: {'content-type': 'application/json'},
      );
    });

    try {
      _server = await shelf_io.serve(
        logRequests().addHandler(app.call),
        InternetAddress.anyIPv4,
        kLanSyncPort,
      );
      hubRunning = true;
      _startPinRotation();
      lastStatus = 'Hosting on ${localIp ?? 'this device'}:$kLanSyncPort';
      await prefs.setBool('lan_prefer_hub', true);
    } catch (e) {
      lastError = 'Could not start hub: $e';
      hubRunning = false;
    }
    notifyListeners();
  }

  Future<void> approvePending(String requestId) async {
    final pending = _pendingById.remove(requestId);
    pendingPairs.removeWhere((p) => p.id == requestId);
    if (pending == null) return;
    final token = _uuid.v4();
    _sessions[token] = SyncPeer(
      deviceId: pending.deviceId,
      name: pending.name,
      platform: pending.platform,
      lastSeen: DateTime.now(),
      address: pending.address,
    );
    _pendingOutcome[requestId] = token;
    await _persistSessions();
    _refreshPeerList();
    lastStatus = 'Approved ${pending.name}';
    notifyListeners();
  }

  Future<void> denyPending(String requestId) async {
    final pending = _pendingById.remove(requestId);
    pendingPairs.removeWhere((p) => p.id == requestId);
    _pendingOutcome[requestId] = 'denied';
    if (pending != null) {
      lastStatus = 'Denied ${pending.name}';
    }
    notifyListeners();
  }

  Future<void> revokePeer(String peerDeviceId) async {
    _sessions.removeWhere((_, p) => p.deviceId == peerDeviceId);
    await _persistSessions();
    _refreshPeerList();
    lastStatus = 'Removed paired device';
    notifyListeners();
  }

  /// User turned hosting off — stop listening and clear auto-restart.
  Future<void> stopHub() async {
    await _shutdownServer(clearPrefer: true);
  }

  Future<void> _shutdownServer({required bool clearPrefer}) async {
    await _server?.close(force: true);
    _server = null;
    // Keep persisted sessions; drop only live pending approvals.
    pendingPairs.clear();
    _pendingById.clear();
    hubRunning = false;
    _stopPinRotation();
    lastStatus = clearPrefer ? 'Hub stopped' : lastStatus;
    if (clearPrefer) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('lan_prefer_hub', false);
    }
    _refreshPeerList();
    notifyListeners();
  }

  void _touch(String token) {
    final p = _sessions[token];
    if (p == null) return;
    _sessions[token] = SyncPeer(
      deviceId: p.deviceId,
      name: p.name,
      platform: p.platform,
      lastSeen: DateTime.now(),
      address: p.address,
    );
    _refreshPeerList();
    unawaited(_persistSessions());
  }

  void _refreshPeerList() {
    connectedPeers
      ..clear()
      ..addAll(_sessions.values);
    notifyListeners();
  }

  // --- Client (multi-hub) ---

  ({String host, int port}) _parseHostPort(String raw, int defaultPort) {
    var h = raw.trim();
    if (h.isEmpty) {
      throw StateError('Enter the host IP shown on the other device.');
    }
    h = h.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    h = h.split('/').first.trim();
    if (h.startsWith('[') && h.contains(']')) {
      final end = h.indexOf(']');
      final inside = h.substring(1, end);
      final rest = h.substring(end + 1);
      if (rest.startsWith(':')) {
        final parsedPort = int.tryParse(rest.substring(1));
        if (parsedPort != null) return (host: inside, port: parsedPort);
      }
      return (host: inside, port: defaultPort);
    }
    final colon = h.lastIndexOf(':');
    if (colon > 0 && h.indexOf(':') == colon) {
      final maybePort = int.tryParse(h.substring(colon + 1));
      if (maybePort != null) {
        return (host: h.substring(0, colon), port: maybePort);
      }
    }
    return (host: h, port: defaultPort);
  }

  Future<HubHello> probeHub({
    required String host,
    int port = kLanSyncPort,
  }) async {
    final parsed = _parseHostPort(host, port);
    final uri = Uri(
      scheme: 'http',
      host: parsed.host,
      port: parsed.port,
      path: '/v1/hello',
    );
    late http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      throw StateError(
        'Timed out reaching ${parsed.host}:${parsed.port}. '
        'Is hosting on, and are both devices on the same Wi‑Fi?',
      );
    } on SocketException catch (e) {
      throw StateError(
        'Cannot reach ${parsed.host}:${parsed.port} (${e.osError?.message ?? e.message}).',
      );
    } on http.ClientException catch (e) {
      throw StateError('Cannot reach ${parsed.host}:${parsed.port} (${e.message}).');
    }
    if (res.statusCode != 200) {
      throw StateError('No Vitalog host at ${parsed.host}:${parsed.port}.');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    if (map['hub'] != true) {
      throw StateError('That address is not a Vitalog host.');
    }
    return HubHello(
      deviceId: map['deviceId'] as String? ?? parsed.host,
      name: map['name'] as String? ?? 'Desktop',
      platform: map['platform'] as String? ?? 'device',
      port: (map['port'] as num?)?.toInt() ?? parsed.port,
    );
  }

  /// Accepts `192.168.1.20` or `192.168.1.20:17843`.
  /// Waits for host approval when this is a first-time pair.
  Future<PairedHub> pairWithHub({
    required String host,
    required String pin,
    int port = kLanSyncPort,
    Duration approvalTimeout = const Duration(minutes: 2),
  }) async {
    lastError = null;
    final parsed = _parseHostPort(host, port);
    final cleanPin = pin.trim();
    if (cleanPin.length != 6) {
      throw StateError('Enter the 6-digit pairing PIN from the host.');
    }
    final uri = Uri(
      scheme: 'http',
      host: parsed.host,
      port: parsed.port,
      path: '/v1/pair',
    );
    late http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'pin': cleanPin,
              'deviceId': deviceId,
              'name': deviceName,
              'platform': platformLabel,
            }),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw StateError(
        'Timed out reaching ${parsed.host}:${parsed.port}. '
        'Is hosting on, and are both devices on the same Wi‑Fi?',
      );
    } on SocketException catch (e) {
      throw StateError(
        'Cannot reach ${parsed.host}:${parsed.port} (${e.osError?.message ?? e.message}). '
        'Check the IP, same Wi‑Fi, and that the host firewall allows port ${parsed.port}.',
      );
    } on http.ClientException catch (e) {
      throw StateError(
        'Cannot reach ${parsed.host}:${parsed.port} (${e.message}). '
        'Same Wi‑Fi? Host still running?',
      );
    }
    if (res.statusCode == 429) {
      throw StateError('Too many wrong PIN tries — wait a minute and try again.');
    }
    if (res.statusCode == 403) {
      throw StateError('Wrong PIN — check the 6 digits on the host.');
    }

    Map<String, dynamic> map;
    if (res.statusCode == 202) {
      map = jsonDecode(res.body) as Map<String, dynamic>;
      final requestId = map['requestId'] as String?;
      if (requestId == null) {
        throw StateError('Host did not return a pairing request id.');
      }
      lastStatus = 'Waiting for approval on ${map['hubName'] ?? 'host'}…';
      notifyListeners();
      map = await _waitForApproval(
        host: parsed.host,
        port: parsed.port,
        requestId: requestId,
        timeout: approvalTimeout,
      );
    } else if (res.statusCode == 200) {
      map = jsonDecode(res.body) as Map<String, dynamic>;
    } else {
      throw StateError(
        'Pairing failed (HTTP ${res.statusCode}). Check Wi‑Fi and try again.',
      );
    }

    if (map['status'] == 'denied') {
      throw StateError('The host denied this device.');
    }
    final token = map['token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('Host did not return a session token.');
    }

    final vaultKey = (map['vaultKey'] as String?)?.trim();
    if (vaultKey == null || vaultKey.length < 6) {
      throw StateError(
        'Host did not share a vault key. Update Vitalog on the host and pair again.',
      );
    }
    final hub = PairedHub(
      deviceId: map['deviceId'] as String? ?? parsed.host,
      name: map['name'] as String? ?? 'Desktop',
      host: parsed.host,
      port: parsed.port,
      token: token,
      // Sticky vault key — never the rotating join PIN.
      pin: vaultKey,
    );
    pairedHubs.removeWhere(
      (h) => h.deviceId == hub.deviceId || h.host == parsed.host,
    );
    pairedHubs.add(hub);
    await _persistHubs();
    lastStatus = 'Paired with ${hub.name}';
    notifyListeners();
    return hub;
  }

  Future<Map<String, dynamic>> _waitForApproval({
    required String host,
    required int port,
    required String requestId,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final statusUri = Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '/v1/pair/status',
        queryParameters: {'requestId': requestId},
      );
      try {
        final res = await http.get(statusUri).timeout(const Duration(seconds: 5));
        if (res.statusCode == 404) {
          throw StateError('Pairing request expired on the host.');
        }
        if (res.statusCode != 200) continue;
        final map = jsonDecode(res.body) as Map<String, dynamic>;
        final status = map['status'] as String?;
        if (status == 'pending') continue;
        return map;
      } catch (e) {
        if (e is StateError) rethrow;
        // Keep polling through brief network blips.
      }
    }
    throw StateError(
      'Timed out waiting for the host to approve this device.',
    );
  }

  Future<void> forgetHub(PairedHub hub) async {
    pairedHubs.removeWhere(
      (h) => h.deviceId == hub.deviceId && h.host == hub.host,
    );
    await _persistHubs();
    notifyListeners();
  }

  Future<List<SyncPeer>> fetchPeers(PairedHub hub) async {
    final uri = Uri.parse('http://${hub.host}:${hub.port}/v1/peers');
    final res = await http
        .get(uri, headers: {'x-vitalog-token': hub.token})
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw StateError('Not connected to ${hub.name}');
    }
    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final peers = <SyncPeer>[
      SyncPeer(
        deviceId: (map['hub'] as Map)['deviceId'] as String? ?? hub.deviceId,
        name: (map['hub'] as Map)['name'] as String? ?? hub.name,
        platform: (map['hub'] as Map)['platform'] as String? ?? 'desktop',
        lastSeen: DateTime.now(),
        address: hub.host,
      ),
      for (final e in (map['peers'] as List? ?? []))
        SyncPeer(
          deviceId: (e as Map)['deviceId'] as String? ?? '',
          name: e['name'] as String? ?? 'Device',
          platform: e['platform'] as String? ?? 'device',
          lastSeen: DateTime.tryParse(e['lastSeen'] as String? ?? ''),
          address: hub.host,
        ),
    ];
    return peers;
  }

  /// ADR-010: auto-sync when hubs are reachable (periodic + debounce).
  void startAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 40), (_) {
      unawaited(syncQuietly());
    });
    unawaited(syncQuietly());
  }

  void stopAutoSync() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }


  void scheduleSyncSoon() {
    if (pairedHubs.isEmpty) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      unawaited(syncQuietly());
    });
  }

  Future<void> syncQuietly() async {
    if (pairedHubs.isEmpty || _syncBusy) return;
    final last = _lastAutoSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 8)) {
      return;
    }
    _syncBusy = true;
    try {
      await syncAllHubs();
      _lastAutoSyncAt = DateTime.now();
      final all = <ReminderRecord>[];
      for (final profile in store.profiles) {
        all.addAll(await store.listReminders(profile.id));
      }
      await ReminderNotifications.instance.rescheduleAll(all);
    } catch (_) {
      // Hub offline / Wi‑Fi changed — next tick retries.
    } finally {
      _syncBusy = false;
    }
  }

  Future<String> syncWithHub(PairedHub hub) async {
    lastError = null;
    final headers = {
      'content-type': 'application/json',
      'x-vitalog-token': hub.token,
    };
    final pullUri = Uri.parse('http://${hub.host}:${hub.port}/v1/vault');
    final pullRes = await http
        .get(pullUri, headers: headers)
        .timeout(const Duration(seconds: 60));
    var pulled = 0;
    if (pullRes.statusCode == 200) {
      final sealed = jsonDecode(pullRes.body) as Map<String, dynamic>;
      final plain = await _open(sealed, hub.pin);
      final r = await store.mergeFromExportJson(plain);
      pulled = r.reportsAdded + r.careRowsAdded;
    } else if (pullRes.statusCode == 403) {
      throw StateError('Session expired — pair again with ${hub.name}');
    }

    final plain = jsonEncode(await store.exportVaultMap());
    final sealed = await _seal(plain, hub.pin);
    final pushUri = Uri.parse('http://${hub.host}:${hub.port}/v1/vault');
    final pushRes = await http
        .post(pushUri, headers: headers, body: jsonEncode(sealed))
        .timeout(const Duration(seconds: 60));
    var pushed = 0;
    if (pushRes.statusCode == 200) {
      final map = jsonDecode(pushRes.body) as Map<String, dynamic>;
      final reports = (map['reportsAdded'] as num?)?.toInt() ?? 0;
      final care = (map['careRowsAdded'] as num?)?.toInt() ?? 0;
      pushed = reports + care;
    }

    lastSyncByDevice[hub.deviceId] = DateTime.now();
    final msg =
        'Synced with ${hub.name}: pulled $pulled, they added $pushed from us (reports + care)';
    lastStatus = msg;
    notifyListeners();
    return msg;
  }

  Future<String> syncAllHubs() async {
    if (pairedHubs.isEmpty) return 'No paired desktops';
    final parts = <String>[];
    for (final h in List<PairedHub>.from(pairedHubs)) {
      try {
        parts.add(await syncWithHub(h));
      } catch (e) {
        parts.add('${h.name}: failed ($e)');
      }
    }
    lastStatus = parts.join(' · ');
    notifyListeners();
    return lastStatus!;
  }

  Future<List<int>> _keyFromPin(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );
    final secret = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return secret.extractBytes();
  }

  Future<Map<String, dynamic>> _seal(String plain, String pin) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final keyBytes = await _keyFromPin(pin, salt);
    final algo = AesGcm.with256bits();
    final secretKey = SecretKey(keyBytes);
    final box = await algo.encrypt(
      utf8.encode(plain),
      secretKey: secretKey,
    );
    return {
      'v': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'cipher': base64Encode(box.cipherText),
    };
  }

  Future<String> _open(Map<String, dynamic> sealed, String pin) async {
    final salt = base64Decode(sealed['salt'] as String);
    final keyBytes = await _keyFromPin(pin, salt);
    final algo = AesGcm.with256bits();
    final clear = await algo.decrypt(
      SecretBox(
        base64Decode(sealed['cipher'] as String),
        nonce: base64Decode(sealed['nonce'] as String),
        mac: Mac(base64Decode(sealed['mac'] as String)),
      ),
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clear);
  }

  @override
  void dispose() {
    // Keep prefer-hub so the channel comes back next launch.
    unawaited(_shutdownServer(clearPrefer: false));
    stopAutoSync();
    super.dispose();
  }
}

class _PinAttemptBucket {
  int failures = 0;
  DateTime? lastAt;
  DateTime? lockedUntil;
}
