import 'package:flutter/foundation.dart';

/// Deep link + QR payload for LAN pair (PIN stays out of the QR).
class PairDeepLinks {
  PairDeepLinks._();

  static const scheme = 'vitalog';
  static const hostPath = 'pair';

  /// Filled when OS opens vitalog://pair?… — SyncScreen consumes it.
  static final pendingHost = ValueNotifier<String?>(null);

  static String encodeHostQr(String ip, {int port = 17843}) {
    return Uri(
      scheme: scheme,
      host: hostPath,
      queryParameters: {'host': '$ip:$port'},
    ).toString();
  }

  /// Accepts vitalog://pair?host=…, plain IP:port, or IP only.
  static String? parseHost(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final uri = Uri.tryParse(s);
    if (uri != null &&
        uri.scheme == scheme &&
        (uri.host == hostPath || uri.pathSegments.contains(hostPath))) {
      final h = uri.queryParameters['host']?.trim();
      if (h != null && h.isNotEmpty) return h;
    }

    // Plain LAN address
    final m = RegExp(r'^(\d{1,3}(?:\.\d{1,3}){3})(?::(\d{2,5}))?$').firstMatch(s);
    if (m != null) {
      final port = m.group(2);
      return port == null ? m.group(1)! : '${m.group(1)}:$port';
    }
    return null;
  }
}
