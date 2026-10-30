import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class DownloadProgress {
  final int downloadedBytes;
  final int? totalBytes;
  final Duration elapsed;

  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.elapsed,
  });

  int? get percent {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return ((downloadedBytes / total) * 100).clamp(0, 100).round();
  }

  double get megabytesPerSecond {
    final seconds = elapsed.inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    return (downloadedBytes / (1024 * 1024)) / seconds;
  }
}

class DownloadService {
  static Future<void> downloadFile(
    String url,
    File file, {
    http.Client? client,
    void Function(DownloadProgress progress)? onProgress,
  }) async {
    final httpClient = client ?? http.Client();
    final ownsClient = client == null;
    final tempFile = File("${file.path}.download");

    try {
      final request = http.Request("GET", Uri.parse(url));
      final response = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception("Erro ao baixar arquivo");
      }

      await file.parent.create(recursive: true);
      final sink = tempFile.openWrite();
      final startedAt = DateTime.now();
      var downloaded = 0;
      try {
        await for (final chunk in response.stream.timeout(
          const Duration(minutes: 10),
        )) {
          downloaded += chunk.length;
          sink.add(chunk);
          onProgress?.call(
            DownloadProgress(
              downloadedBytes: downloaded,
              totalBytes: response.contentLength,
              elapsed: DateTime.now().difference(startedAt),
            ),
          );
        }
      } finally {
        await sink.close();
      }

      if (await tempFile.length() == 0) {
        throw Exception("Arquivo baixado vazio");
      }

      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }
}
