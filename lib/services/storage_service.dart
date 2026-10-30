import 'dart:io';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const String _invalidChars = '<>:"/\\|?*';

  static bool _hasInvalidChars(String value) {
    return value.codeUnits.any((code) {
      return code < 32 || _invalidChars.contains(String.fromCharCode(code));
    });
  }

  static String safeFileName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.contains("/") ||
        name.contains("\\") ||
        name.contains("..") ||
        name == "." ||
        name == ".." ||
        name.length > 180 ||
        _hasInvalidChars(name)) {
      throw const FormatException("Nome de arquivo invalido");
    }
    return name;
  }

  static String safeFolderName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.contains("/") ||
        name.contains("\\") ||
        name.contains("..") ||
        name == "." ||
        name == ".." ||
        name.length > 80 ||
        _hasInvalidChars(name)) {
      throw const FormatException("Nome da TV invalido");
    }
    return name;
  }

  static Future<Directory> getTvFolder(String tv) async {
    Directory baseDir;
    final safeTv = safeFolderName(tv);

    try {
      // 🔥 PRIORIDADE: EXTERNAL (visível)
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        baseDir = ext;
      } else {
        throw Exception("External null");
      }
    } catch (_) {
      // 🔥 FALLBACK: INTERNAL (seguro)
      baseDir = await getApplicationDocumentsDirectory();
    }

    final folder = Directory("${baseDir.path}${Platform.pathSeparator}$safeTv");

    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }

    return folder;
  }

  static File getFile(Directory dir, String fileName) {
    return File(
      "${dir.path}${Platform.pathSeparator}${safeFileName(fileName)}",
    );
  }

  static bool isPlayableMediaFileName(String fileName) {
    final name = fileName.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.mp4');
  }

  static void cleanOldFiles(Directory dir, List<String> valid) {
    final files = dir.listSync().whereType<File>();

    for (final f in files) {
      if (f.path.endsWith(PlaybackFileNames.pendingEvents)) {
        continue;
      }
      final name = f.uri.pathSegments.isNotEmpty
          ? f.uri.pathSegments.last
          : f.path.split(Platform.pathSeparator).last;

      if (!valid.contains(name)) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
  }

  static bool hasValidLocalFile(Directory dir, String fileName) {
    if (!isPlayableMediaFileName(fileName)) return false;
    final file = getFile(dir, fileName);
    return file.existsSync() && file.lengthSync() > 0;
  }
}

class PlaybackFileNames {
  static const String pendingEvents = 'playback_events_pending.jsonl';
}
