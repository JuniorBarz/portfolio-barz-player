import 'dart:convert';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'api_service.dart';

typedef VersionProvider = Future<String> Function();
typedef FreeSpaceProvider = Future<int?> Function();

class TelemetrySnapshot {
  final String? currentMedia;
  final String? downloadStatus;
  final int? apiLatencyMs;
  final String? lastError;
  final bool reportLastError;

  const TelemetrySnapshot({
    this.currentMedia,
    this.downloadStatus,
    this.apiLatencyMs,
    this.lastError,
    this.reportLastError = false,
  });

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    if (currentMedia != null) data['current_media'] = currentMedia;
    if (downloadStatus != null) data['download_status'] = downloadStatus;
    if (apiLatencyMs != null) data['api_latency_ms'] = apiLatencyMs;
    if (lastError != null) {
      data['last_error'] = TelemetryService.sanitizeError(lastError!);
    } else if (reportLastError) {
      data['last_error'] = null;
    }
    return data;
  }
}

class TelemetryService {
  static String? _cachedVersion;

  static Uri statusUri(String ip, String porta, String tv) {
    return buildScreenEndpointUri(
      host: ip,
      port: parseServicePort(porta),
      channel: tv,
      action: 'status',
    );
  }

  static String sanitizeError(Object error) {
    final value = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length <= 500 ? value : value.substring(0, 500);
  }

  static Future<String> _appVersion() async {
    return _cachedVersion ??= (await PackageInfo.fromPlatform()).version;
  }

  static Future<int?> _freeSpaceBytes() async {
    final megabytes = await DiskSpacePlus().getFreeDiskSpace;
    if (megabytes == null || megabytes < 0) return null;
    return (megabytes * 1024 * 1024).round();
  }

  static Future<void> send({
    required String ip,
    required String porta,
    required String tv,
    required TelemetrySnapshot snapshot,
    http.Client? client,
    VersionProvider? versionProvider,
    FreeSpaceProvider? freeSpaceProvider,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final data = snapshot.toJson();
      final version = await (versionProvider ?? _appVersion)();
      final freeSpace = await (freeSpaceProvider ?? _freeSpaceBytes)();
      data['app_version'] = version;
      if (freeSpace != null) data['free_space_bytes'] = freeSpace;
      await httpClient
          .post(
            statusUri(ip, porta, tv),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Telemetry is best-effort and must never interrupt playback.
    } finally {
      if (ownsClient) httpClient.close();
    }
  }
}
