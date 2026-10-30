import 'dart:convert';

import 'package:barz_player/models/media_item.dart';
import 'package:barz_player/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FakeClient extends http.BaseClient {
  final List<http.Request> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(
          '{"screen_id":"showroom","revision":1,"items":['
          '{"id":"offer-loop","kind":"video",'
          '"url":"/media/showroom/offer loop.mp4","duration_seconds":30}]}',
        ),
      ),
      200,
    );
  }
}

void main() {
  test('builds a validated and encoded playlist URI', () {
    final uri = buildPlaylistUri(
      host: '192.0.2.10',
      port: 8502,
      channel: 'showroom west',
    );

    expect(
      uri.toString(),
      'http://192.0.2.10:8502/api/screens/showroom%20west/playlist',
    );
  });

  test('rejects malformed endpoint configuration', () {
    for (final host in ['', 'https://example.test', 'example.test/path', 'host?x=1']) {
      expect(
        () => buildPlaylistUri(host: host, port: 8502, channel: 'showroom'),
        throwsArgumentError,
      );
    }
    for (final port in [0, 65536]) {
      expect(
        () => buildPlaylistUri(host: 'example.test', port: port, channel: 'showroom'),
        throwsArgumentError,
      );
    }
    expect(
      () => buildPlaylistUri(host: 'example.test', port: 8502, channel: ''),
      throwsArgumentError,
    );
  });

  test('builds encoded media uri for file names with spaces', () {
    final item = MediaItem(
      file: 'padaria 2.mp4',
      tipo: 'video',
      url: '/media/padaria/padaria 2.mp4',
    );

    final uri = ApiService.mediaUri('192.0.2.10', '8502', item);

    expect(
      uri.toString(),
      'http://192.0.2.10:8502/media/padaria/padaria%202.mp4',
    );
  });

  test('fetch result includes playlist latency', () async {
    final client = FakeClient();

    final result = await ApiService.fetchPlaylistWithMetrics(
      '192.0.2.10',
      '8502',
      'showroom',
      client: client,
    );

    expect(result.items.single.file, 'offer loop.mp4');
    expect(result.latencyMs, greaterThanOrEqualTo(0));
    expect(client.requests.single.url.path, '/api/screens/showroom/playlist');
  });
}
