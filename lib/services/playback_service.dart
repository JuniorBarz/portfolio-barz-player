import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/media_item.dart';
import 'api_service.dart';

class PlaybackService {
  static const String pendingFileName = 'playback_events_pending.jsonl';
  static const int _maxPendingEvents = 1000;
  static const int _maxFlushBatch = 100;
  static final Map<String, Future<void>> _operationTails = {};

  static File pendingFile(Directory dir) {
    return File('${dir.path}${Platform.pathSeparator}$pendingFileName');
  }

  static Map<String, dynamic> eventFromItem(
    MediaItem item, {
    int? durationSeconds,
  }) {
    return {
      'file': item.file,
      'tipo': item.tipo,
      'duration_seconds':
          durationSeconds ?? (item.tipo == 'imagem' ? (item.tempo ?? 5) : 0),
    };
  }

  static Future<void> queueEvent(
    Directory dir,
    MediaItem item, {
    int? durationSeconds,
  }) {
    return _serialized(dir, () async {
      await _queueEventUnlocked(dir, item, durationSeconds: durationSeconds);
    });
  }

  static Future<void> _queueEventUnlocked(
    Directory dir,
    MediaItem item, {
    int? durationSeconds,
  }) async {
    final file = pendingFile(dir);
    await file.parent.create(recursive: true);
    final events = await _readPendingEventsUnlocked(dir);
    final event = eventFromItem(item, durationSeconds: durationSeconds);
    events.add(event);
    final bounded = events.length <= _maxPendingEvents
        ? events
        : events.sublist(events.length - _maxPendingEvents);
    await _replaceQueueUnlocked(dir, bounded);
  }

  static Future<List<Map<String, dynamic>>> readPendingEvents(Directory dir) {
    return _serialized(dir, () => _readPendingEventsUnlocked(dir));
  }

  static Future<List<Map<String, dynamic>>> _readPendingEventsUnlocked(
    Directory dir,
  ) async {
    final file = pendingFile(dir);
    await _recoverTemporaryQueue(file);
    if (!await file.exists()) return [];
    final lines = await file.readAsLines(encoding: utf8);
    final events = <Map<String, dynamic>>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (_isValidEvent(decoded)) {
          events.add(decoded as Map<String, dynamic>);
        }
      } on FormatException {
        continue;
      }
    }
    if (events.length <= _maxPendingEvents) return events;
    return events.sublist(events.length - _maxPendingEvents);
  }

  static bool _isValidEvent(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    final file = value['file'];
    final tipo = value['tipo'];
    final durationSeconds = value['duration_seconds'];
    return file is String &&
        file.trim().isNotEmpty &&
        tipo is String &&
        (tipo == 'imagem' || tipo == 'video') &&
        durationSeconds is int &&
        durationSeconds >= 0;
  }

  static Uri playbackUri(String ip, String porta, String tv) {
    return buildScreenEndpointUri(
      host: ip,
      port: parseServicePort(porta),
      channel: tv,
      action: 'playback',
    );
  }

  static Future<void> flushPending({
    required Directory dir,
    required String ip,
    required String porta,
    required String tv,
    http.Client? client,
  }) {
    return _serialized(
      dir,
      () => _flushPendingUnlocked(
        dir: dir,
        ip: ip,
        porta: porta,
        tv: tv,
        client: client,
      ),
    );
  }

  static Future<void> _flushPendingUnlocked({
    required Directory dir,
    required String ip,
    required String porta,
    required String tv,
    http.Client? client,
  }) async {
    final events = await _readPendingEventsUnlocked(dir);
    if (events.isEmpty) {
      await _replaceQueueUnlocked(dir, const []);
      return;
    }

    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    var sentCount = 0;
    final batchSize = events.length < _maxFlushBatch
        ? events.length
        : _maxFlushBatch;

    try {
      for (var index = 0; index < batchSize; index++) {
        final event = events[index];
        try {
          final response = await httpClient
              .post(
                playbackUri(ip, porta, tv),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(event),
              )
              .timeout(const Duration(seconds: 8));
          if (response.statusCode < 200 || response.statusCode >= 300) {
            break;
          }
          sentCount++;
        } catch (_) {
          break;
        }
      }
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }

    await _replaceQueueUnlocked(dir, events.sublist(sentCount));
  }

  static Future<void> recordAndFlush({
    required Directory dir,
    required String ip,
    required String porta,
    required String tv,
    required MediaItem item,
    int? durationSeconds,
    http.Client? client,
  }) {
    return _serialized(dir, () async {
      await _queueEventUnlocked(dir, item, durationSeconds: durationSeconds);
      await _flushPendingUnlocked(
        dir: dir,
        ip: ip,
        porta: porta,
        tv: tv,
        client: client,
      );
    });
  }

  static Future<T> _serialized<T>(
    Directory dir,
    Future<T> Function() operation,
  ) {
    final key = dir.absolute.path;
    final previous = _operationTails[key] ?? Future<void>.value();
    final turn = Completer<void>();
    _operationTails[key] = turn.future;

    return previous.then((_) => operation()).whenComplete(() {
      if (!turn.isCompleted) turn.complete();
      if (identical(_operationTails[key], turn.future)) {
        _operationTails.remove(key);
      }
    });
  }

  static File _temporaryFile(File file) => File('${file.path}.tmp');

  static Future<void> _recoverTemporaryQueue(File file) async {
    final temporary = _temporaryFile(file);
    if (!await temporary.exists()) return;
    if (await file.exists()) {
      await temporary.delete();
      return;
    }
    await temporary.rename(file.path);
  }

  static Future<void> _replaceQueueUnlocked(
    Directory dir,
    List<Map<String, dynamic>> events,
  ) async {
    final file = pendingFile(dir);
    final temporary = _temporaryFile(file);
    if (events.isEmpty) {
      if (await temporary.exists()) await temporary.delete();
      if (await file.exists()) await file.delete();
      return;
    }

    await file.parent.create(recursive: true);
    await temporary.writeAsString(
      '${events.map(jsonEncode).join('\n')}\n',
      encoding: utf8,
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
