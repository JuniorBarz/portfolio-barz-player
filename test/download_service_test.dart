import 'dart:async';
import 'dart:io';

import 'package:barz_player/services/download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reports download progress while writing file', () async {
    final dir = await Directory.systemTemp.createTemp('barz-download-test-');
    final file = File('${dir.path}${Platform.pathSeparator}video.mp4');
    final progresses = <DownloadProgress>[];

    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4],
        ]),
        200,
        contentLength: 4,
      );
    });

    try {
      await DownloadService.downloadFile(
        'http://127.0.0.1/video.mp4',
        file,
        client: client,
        onProgress: progresses.add,
      );

      expect(await file.length(), 4);
      expect(progresses.map((p) => p.downloadedBytes), [2, 4]);
      expect(progresses.last.totalBytes, 4);
      expect(progresses.last.percent, 100);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
