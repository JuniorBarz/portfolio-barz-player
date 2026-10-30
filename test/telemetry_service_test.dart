import 'dart:convert';

import 'package:barz_player/services/telemetry_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FakeClient extends http.BaseClient {
  final List<http.Request> requests = [];
  Object? error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (error != null) throw error!;
    requests.add(request as http.Request);
    return http.StreamedResponse(Stream.value(utf8.encode('{"ok":true}')), 200);
  }
}

void main() {
  test('builds encoded status uri', () {
    expect(
      TelemetryService.statusUri(
        '192.0.2.10',
        '8502',
        'padaria nova',
      ).toString(),
      'http://192.0.2.10:8502/api/screens/padaria%20nova/status',
    );
  });

  test('snapshot omits unset fields and can clear last error', () {
    final snapshot = TelemetrySnapshot(
      currentMedia: 'oferta.mp4',
      reportLastError: true,
    );

    expect(snapshot.toJson(), {
      'current_media': 'oferta.mp4',
      'last_error': null,
    });
  });

  test('send adds device data and truncates errors', () async {
    final client = FakeClient();

    await TelemetryService.send(
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'padaria',
      snapshot: TelemetrySnapshot(lastError: 'x' * 700),
      client: client,
      versionProvider: () async => '1.1.0',
      freeSpaceProvider: () async => 123456,
    );

    final body =
        jsonDecode(client.requests.single.body) as Map<String, dynamic>;
    expect(body['app_version'], '1.1.0');
    expect(body['free_space_bytes'], 123456);
    expect((body['last_error'] as String).length, 500);
  });

  test('network failure never propagates', () async {
    final client = FakeClient()..error = Exception('offline');

    await TelemetryService.send(
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'padaria',
      snapshot: const TelemetrySnapshot(downloadStatus: 'ocioso'),
      client: client,
      versionProvider: () async => '1.1.0',
      freeSpaceProvider: () async => 123456,
    );
  });
}
