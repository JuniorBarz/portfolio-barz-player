import 'dart:io';

import 'package:barz_player/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects traversal file names', () {
    expect(
      () => StorageService.safeFileName('..\\secret.mp4'),
      throwsFormatException,
    );
  });

  test('trims safe folder names', () {
    expect(StorageService.safeFolderName(' Sala 1 '), 'Sala 1');
  });

  test('accepts safe names with spaces', () {
    expect(StorageService.safeFolderName('Padaria'), 'Padaria');
    expect(StorageService.safeFileName('midia do dia.jpg'), 'midia do dia.jpg');
  });

  test('detects valid local files only when file exists with bytes', () async {
    final dir = await Directory.systemTemp.createTemp('barz-storage-test-');
    final file = File('${dir.path}${Platform.pathSeparator}video.mp4');

    try {
      expect(StorageService.hasValidLocalFile(dir, 'video.mp4'), isFalse);

      await file.writeAsBytes([]);
      expect(StorageService.hasValidLocalFile(dir, 'video.mp4'), isFalse);

      await file.writeAsBytes([1, 2, 3]);
      expect(StorageService.hasValidLocalFile(dir, 'video.mp4'), isTrue);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('rejects non media files as playable local files', () async {
    final dir = await Directory.systemTemp.createTemp('barz-storage-test-');
    final file = File(
      '${dir.path}${Platform.pathSeparator}playback_events_pending.jsonl',
    );

    try {
      await file.writeAsString('{}');

      expect(
        StorageService.hasValidLocalFile(dir, 'playback_events_pending.jsonl'),
        isFalse,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
