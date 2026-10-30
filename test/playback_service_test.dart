import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:barz_player/models/media_item.dart';
import 'package:barz_player/services/playback_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class FakeClient extends http.BaseClient {
  final List<http.Request> requests = [];
  int statusCode = 200;
  Completer<void>? firstRequestGate;
  final Completer<void> firstRequestStarted = Completer<void>();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request as http.Request);
    if (requests.length == 1) {
      if (!firstRequestStarted.isCompleted) {
        firstRequestStarted.complete();
      }
      if (firstRequestGate case final gate?) {
        await gate.future;
      }
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"ok":true}')),
      statusCode,
    );
  }
}

void main() {
  test('queues playback event as jsonl', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    final item = MediaItem(
      file: 'mídia.jpg',
      tipo: 'imagem',
      tempo: 5,
      url: '/media/sala/mídia.jpg',
    );

    await PlaybackService.queueEvent(dir, item);

    final lines = await PlaybackService.readPendingEvents(dir);
    expect(lines, hasLength(1));
    expect(lines.first['file'], 'mídia.jpg');
    expect(lines.first['duration_seconds'], 5);
  });

  test('flush sends pending events and clears queue', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    final item = MediaItem(
      file: 'video.mp4',
      tipo: 'video',
      tempo: null,
      url: '/media/sala/video.mp4',
    );
    final client = FakeClient();
    await PlaybackService.queueEvent(dir, item);

    await PlaybackService.flushPending(
      dir: dir,
      ip: '192.0.2.10',
      porta: '8000',
      tv: 'sala',
      client: client,
    );

    expect(client.requests, hasLength(1));
    expect(client.requests.single.url.path, '/api/screens/sala/playback');
    expect(await PlaybackService.readPendingEvents(dir), isEmpty);
  });

  test('video event uses measured duration', () {
    final item = MediaItem(
      file: 'video.mp4',
      tipo: 'video',
      url: '/media/sala/video.mp4',
    );

    expect(PlaybackService.eventFromItem(item, durationSeconds: 42), {
      'file': 'video.mp4',
      'tipo': 'video',
      'duration_seconds': 42,
    });
  });

  test('skips corrupt queue lines and invalid event shapes', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = PlaybackService.pendingFile(dir);
    await file.writeAsString(
      '{"file":"first.mp4","tipo":"video","duration_seconds":44}\n'
      ':44}\n'
      '{"file":"missing-fields.mp4"}\n'
      '[]\n'
      '{"file":"second.jpg","tipo":"imagem","duration_seconds":5}\n',
    );

    final events = await PlaybackService.readPendingEvents(dir);

    expect(events, hasLength(2));
    expect(events.first['file'], 'first.mp4');
    expect(events.last['file'], 'second.jpg');
  });

  test('keeps only the newest one thousand valid events', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = PlaybackService.pendingFile(dir);
    final lines = List.generate(
      1001,
      (index) =>
          '{"file":"video-$index.mp4","tipo":"video","duration_seconds":1}',
    );
    await file.writeAsString('${lines.join('\n')}\n');

    final events = await PlaybackService.readPendingEvents(dir);

    expect(events, hasLength(1000));
    expect(events.first['file'], 'video-1.mp4');
    expect(events.last['file'], 'video-1000.mp4');
  });

  test('does not lose an event queued while a flush is in progress', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final first = MediaItem(
      file: 'first.mp4',
      tipo: 'video',
      url: '/media/sala/first.mp4',
    );
    final second = MediaItem(
      file: 'second.mp4',
      tipo: 'video',
      url: '/media/sala/second.mp4',
    );
    final client = FakeClient()..firstRequestGate = Completer<void>();
    await PlaybackService.queueEvent(dir, first, durationSeconds: 10);

    final flush = PlaybackService.flushPending(
      dir: dir,
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'sala',
      client: client,
    );
    await client.firstRequestStarted.future;
    var queueCompleted = false;
    final queue = PlaybackService.queueEvent(
      dir,
      second,
      durationSeconds: 20,
    ).whenComplete(() => queueCompleted = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(queueCompleted, isFalse);
    client.firstRequestGate!.complete();
    await Future.wait([flush, queue]);

    final events = await PlaybackService.readPendingEvents(dir);
    expect(events, hasLength(1));
    expect(events.single['file'], 'second.mp4');
  });

  test('stops at first failed request and keeps all pending events', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final client = FakeClient()..statusCode = 500;
    for (var index = 0; index < 3; index++) {
      await PlaybackService.queueEvent(
        dir,
        MediaItem(
          file: 'video-$index.mp4',
          tipo: 'video',
          url: '/media/sala/video-$index.mp4',
        ),
        durationSeconds: index + 1,
      );
    }

    await PlaybackService.flushPending(
      dir: dir,
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'sala',
      client: client,
    );

    expect(client.requests, hasLength(1));
    expect(await PlaybackService.readPendingEvents(dir), hasLength(3));
  });

  test('sends at most one hundred events per flush', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = PlaybackService.pendingFile(dir);
    final lines = List.generate(
      150,
      (index) =>
          '{"file":"video-$index.mp4","tipo":"video","duration_seconds":1}',
    );
    await file.writeAsString('${lines.join('\n')}\n');
    final client = FakeClient();

    await PlaybackService.flushPending(
      dir: dir,
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'sala',
      client: client,
    );

    expect(client.requests, hasLength(100));
    final remaining = await PlaybackService.readPendingEvents(dir);
    expect(remaining, hasLength(50));
    expect(remaining.first['file'], 'video-100.mp4');
  });

  test('record and flush uses the serialized queue path', () async {
    final dir = await Directory.systemTemp.createTemp('playback-test-');
    addTearDown(() => dir.delete(recursive: true));
    final client = FakeClient();
    final item = MediaItem(
      file: 'current.mp4',
      tipo: 'video',
      url: '/media/sala/current.mp4',
    );

    await PlaybackService.recordAndFlush(
      dir: dir,
      ip: '192.0.2.10',
      porta: '8502',
      tv: 'sala',
      item: item,
      durationSeconds: 44,
      client: client,
    );

    expect(client.requests, hasLength(1));
    expect(await PlaybackService.readPendingEvents(dir), isEmpty);
  });

  test(
    'keeps the valid queue when a temporary write was interrupted',
    () async {
      final dir = await Directory.systemTemp.createTemp('playback-test-');
      addTearDown(() => dir.delete(recursive: true));
      final file = PlaybackService.pendingFile(dir);
      final temporary = File('${file.path}.tmp');
      await file.writeAsString(
        '{"file":"original.mp4","tipo":"video","duration_seconds":44}\n',
      );
      await temporary.writeAsString(':44}');

      final events = await PlaybackService.readPendingEvents(dir);

      expect(events, hasLength(1));
      expect(events.single['file'], 'original.mp4');
      expect(await temporary.exists(), isFalse);
    },
  );
}
