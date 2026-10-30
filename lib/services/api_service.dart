import 'dart:convert';

import 'package:barz_player/models/media_item.dart';
import 'package:http/http.dart' as http;

int parseServicePort(String value) {
  final normalized = value.trim();
  final port = int.tryParse(normalized);
  if (port == null || port < 1 || port > 65535) {
    throw ArgumentError.value(value, 'port', 'use a number from 1 to 65535');
  }
  return port;
}

void _validateHost(String host) {
  if (host.isEmpty || host != host.trim()) {
    throw ArgumentError.value(host, 'host', 'host is required');
  }
  if (RegExp(r'[\s/:?#@\\]').hasMatch(host)) {
    throw ArgumentError.value(host, 'host', 'use only a hostname or IP address');
  }
  final candidate = Uri(scheme: 'http', host: host);
  if (candidate.host != host) {
    throw ArgumentError.value(host, 'host', 'host is invalid');
  }
}

String _validateChannel(String channel) {
  final normalized = channel.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(channel, 'channel', 'channel is required');
  }
  if (normalized != channel || channel.contains('/') || channel.contains('\\')) {
    throw ArgumentError.value(channel, 'channel', 'channel must be one path segment');
  }
  return normalized;
}

Uri buildScreenEndpointUri({
  required String host,
  required int port,
  required String channel,
  required String action,
}) {
  _validateHost(host);
  if (port < 1 || port > 65535) {
    throw ArgumentError.value(port, 'port', 'use a number from 1 to 65535');
  }
  if (action.isEmpty || action.contains('/')) {
    throw ArgumentError.value(action, 'action', 'action must be one path segment');
  }
  return Uri(
    scheme: 'http',
    host: host,
    port: port,
    pathSegments: ['api', 'screens', _validateChannel(channel), action],
  );
}

Uri buildPlaylistUri({
  required String host,
  required int port,
  required String channel,
}) {
  return buildScreenEndpointUri(
    host: host,
    port: port,
    channel: channel,
    action: 'playlist',
  );
}

class PlaylistFetchResult {
  final List<MediaItem> items;
  final int latencyMs;

  const PlaylistFetchResult({required this.items, required this.latencyMs});
}

class ApiService {
  static Uri mediaUri(String host, String portValue, MediaItem item) {
    _validateHost(host);
    final port = parseServicePort(portValue);
    final media = Uri.parse(item.url);
    if (media.hasScheme) {
      if (media.scheme != 'https' || media.host.isEmpty) {
        throw const FormatException('Absolute media URLs must use HTTPS');
      }
      return media;
    }
    if (!item.url.startsWith('/media/')) {
      throw const FormatException('Relative media URL must start with /media/');
    }
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      pathSegments: media.pathSegments.where((part) => part.isNotEmpty),
    );
  }

  static Future<List<MediaItem>> fetchPlaylist(
    String host,
    String portValue,
    String channel,
  ) async {
    return (await fetchPlaylistWithMetrics(host, portValue, channel)).items;
  }

  static Future<PlaylistFetchResult> fetchPlaylistWithMetrics(
    String host,
    String portValue,
    String channel, {
    http.Client? client,
  }) async {
    final url = buildPlaylistUri(
      host: host,
      port: parseServicePort(portValue),
      channel: channel,
    );
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    final stopwatch = Stopwatch()..start();
    try {
      final response = await httpClient
          .get(url)
          .timeout(const Duration(seconds: 12));
      stopwatch.stop();
      if (response.statusCode != 200) {
        throw Exception('Playlist request failed');
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic> || data['items'] is! List) {
        throw const FormatException('Invalid playlist response');
      }
      return PlaylistFetchResult(
        items: (data['items'] as List)
            .whereType<Map<String, dynamic>>()
            .map(_mediaItemFromPublicApi)
            .toList(),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      if (ownsClient) httpClient.close();
    }
  }
}

MediaItem _mediaItemFromPublicApi(Map<String, dynamic> value) {
  final id = value['id'];
  final kind = value['kind'];
  final url = value['url'];
  final duration = value['duration_seconds'];
  if (id is! String || id.trim().isEmpty) {
    throw const FormatException('Invalid media id');
  }
  if (kind != 'image' && kind != 'video') {
    throw const FormatException('Invalid media kind');
  }
  if (url is! String || url.trim().isEmpty) {
    throw const FormatException('Invalid media URL');
  }
  final parsed = Uri.tryParse(url);
  if (parsed == null || parsed.pathSegments.isEmpty) {
    throw const FormatException('Invalid media URL');
  }
  if (parsed.hasScheme && (parsed.scheme != 'https' || parsed.host.isEmpty)) {
    throw const FormatException('Absolute media URLs must use HTTPS');
  }
  if (!parsed.hasScheme && !url.startsWith('/media/')) {
    throw const FormatException('Relative media URL must start with /media/');
  }
  if (duration is! int || duration < 1 || duration > 3600) {
    throw const FormatException('Invalid media duration');
  }
  return MediaItem(
    file: parsed.pathSegments.last,
    tipo: kind == 'image' ? 'imagem' : 'video',
    tempo: duration,
    url: url,
  );
}
