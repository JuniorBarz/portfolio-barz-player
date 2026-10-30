// MEDIA PLAYER COM WATCHDOG INTELIGENTE (SEM QUEBRAR LÓGICA)
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/media_item.dart';

int playbackDurationSeconds(MediaItem item, {Duration? videoDuration}) {
  if (item.tipo == 'imagem') return item.tempo ?? 5;
  final seconds = videoDuration?.inSeconds ?? 0;
  return seconds < 0 ? 0 : seconds;
}

class MediaPlayer extends StatefulWidget {
  final List<MediaItem> playlist;
  final Directory folder;
  final void Function(MediaItem item, int durationSeconds)? onPlaybackStarted;
  final void Function(String message)? onPlaybackIssue;

  const MediaPlayer({
    super.key,
    required this.playlist,
    required this.folder,
    this.onPlaybackStarted,
    this.onPlaybackIssue,
  });

  @override
  State<MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<MediaPlayer> {
  int index = 0;
  VideoPlayerController? controller;
  Timer? timer;
  Timer? watchdog;
  Timer? videoWaitTimer;
  Timer? videoHealthTimer;
  int retryCount = 0;
  bool aguardandoVideo = false;
  bool advancing = false;
  int playToken = 0;
  Duration lastVideoPosition = Duration.zero;
  DateTime lastVideoProgressAt = DateTime.now();
  String? playerMessage;

  bool isImage(String file) {
    final f = file.toLowerCase();
    return f.endsWith(".png") ||
        f.endsWith(".jpg") ||
        f.endsWith(".jpeg") ||
        f.endsWith(".webp");
  }

  @override
  void initState() {
    super.initState();
    _play();

    // 🔥 WATCHDOG PRINCIPAL (10 MIN)
    watchdog = Timer.periodic(const Duration(minutes: 10), (_) {
      _checkReset();
    });
  }

  @override
  void didUpdateWidget(covariant MediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playlist.isEmpty) {
      index = 0;
      timer?.cancel();
      videoHealthTimer?.cancel();
      playerMessage = "Sem midias na playlist";
      return;
    }
    if (index >= widget.playlist.length) {
      index = 0;
      _play();
      return;
    }
    final oldFile =
        oldWidget.playlist.isNotEmpty && index < oldWidget.playlist.length
        ? oldWidget.playlist[index].file
        : null;
    final newFile = widget.playlist[index].file;
    if (oldFile != newFile) {
      _play();
    }
  }

  void _checkReset() {
    if (widget.playlist.isEmpty) return;

    final item = widget.playlist[index];

    // 🖼️ IMAGEM → reinicia direto
    if (isImage(item.file)) {
      _play();
      return;
    }

    // 🎬 VÍDEO → espera terminar
    if (!aguardandoVideo) {
      aguardandoVideo = true;
      _waitVideoToFinish();
    }
  }

  void _waitVideoToFinish() {
    videoWaitTimer?.cancel();

    videoWaitTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      final c = controller;

      if (c == null || !c.value.isInitialized) return;

      final terminou =
          c.value.position >= c.value.duration && !c.value.isPlaying;

      if (terminou) {
        t.cancel();
        aguardandoVideo = false;
        _play(); // 🔥 reset seguro
      }
    });
  }

  int? _findPlayableIndex(int start) {
    if (widget.playlist.isEmpty) return null;

    for (var offset = 0; offset < widget.playlist.length; offset++) {
      final candidate = (start + offset) % widget.playlist.length;
      final item = widget.playlist[candidate];
      final file = File("${widget.folder.path}/${item.file}");
      if (file.existsSync() && file.lengthSync() > 0) {
        return candidate;
      }
    }

    return null;
  }

  void _setPlayerIssue(String message) {
    playerMessage = message;
    widget.onPlaybackIssue?.call(message);
    if (mounted) {
      setState(() {});
    }
  }

  void _startVideoHealthWatch(int token) {
    videoHealthTimer?.cancel();
    lastVideoPosition = Duration.zero;
    lastVideoProgressAt = DateTime.now();

    videoHealthTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || token != playToken) return;
      final c = controller;
      if (c == null || !c.value.isInitialized) return;

      if (c.value.hasError) {
        _setPlayerIssue(
          "Erro no video: ${c.value.errorDescription ?? 'desconhecido'}",
        );
        _retryCurrentOrNext();
        return;
      }

      final position = c.value.position;
      if (position > lastVideoPosition) {
        lastVideoPosition = position;
        lastVideoProgressAt = DateTime.now();
        return;
      }

      final stuckFor = DateTime.now().difference(lastVideoProgressAt);
      final finished =
          c.value.position + const Duration(milliseconds: 500) >=
              c.value.duration &&
          !c.value.isPlaying;

      if (!finished && stuckFor > const Duration(seconds: 90)) {
        _setPlayerIssue("Video travado, reiniciando...");
        _retryCurrentOrNext();
      }
    });
  }

  void _retryCurrentOrNext() {
    if (retryCount < 2) {
      retryCount++;
      Future.delayed(const Duration(milliseconds: 800), _play);
      return;
    }

    retryCount = 0;
    _next();
  }

  void _play() async {
    final token = ++playToken;
    timer?.cancel();
    videoHealthTimer?.cancel();
    advancing = false;
    playerMessage = null;

    try {
      await controller?.dispose();
    } catch (_) {}

    if (widget.playlist.isEmpty) {
      _setPlayerIssue("Sem midias na playlist");
      return;
    }

    final playableIndex = _findPlayableIndex(index);
    if (playableIndex == null) {
      _setPlayerIssue("Nenhum arquivo local valido para reproduzir");
      return;
    }

    index = playableIndex;

    final item = widget.playlist[index];
    final file = File("${widget.folder.path}/${item.file}");

    if (!file.existsSync() || file.lengthSync() == 0) {
      _next();
      return;
    }

    // 🖼️ IMAGEM
    if (isImage(item.file)) {
      retryCount = 0;
      widget.onPlaybackStarted?.call(item, playbackDurationSeconds(item));
      if (mounted) {
        setState(() {});
      }
      timer = Timer(Duration(seconds: item.tempo ?? 5), _next);
      return;
    }

    // 🎬 VIDEO
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || token != playToken) return;

      controller = VideoPlayerController.file(file);

      await controller!.initialize().timeout(const Duration(seconds: 25));

      if (!mounted || token != playToken) return;

      await controller!.play();
      widget.onPlaybackStarted?.call(
        item,
        playbackDurationSeconds(
          item,
          videoDuration: controller!.value.duration,
        ),
      );
      _startVideoHealthWatch(token);

      controller!.addListener(() {
        final c = controller;
        if (c == null || !c.value.isInitialized || token != playToken) return;

        if (c.value.hasError) {
          _setPlayerIssue(
            "Erro no video: ${c.value.errorDescription ?? 'desconhecido'}",
          );
          _retryCurrentOrNext();
          return;
        }

        final finished =
            c.value.position + const Duration(milliseconds: 500) >=
                c.value.duration &&
            !c.value.isPlaying;

        if (finished) {
          _next();
        }
      });

      retryCount = 0;

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _setPlayerIssue("Falha ao iniciar ${item.file}: $error");
      _retryCurrentOrNext();
    }
  }

  void _next() {
    if (widget.playlist.isEmpty) return;
    if (advancing) return;
    advancing = true;
    index = (index + 1) % widget.playlist.length;
    Future.microtask(_play);
  }

  @override
  void dispose() {
    timer?.cancel();
    watchdog?.cancel();
    videoWaitTimer?.cancel();
    videoHealthTimer?.cancel();
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playlist.isEmpty) {
      return const _PlayerMessage(message: "Sem midias na playlist");
    }

    final item = widget.playlist[index];
    final file = File("${widget.folder.path}/${item.file}");

    if (playerMessage != null) {
      return _PlayerMessage(message: playerMessage!);
    }

    if (!file.existsSync() || file.lengthSync() == 0) {
      return const _PlayerMessage(message: "Arquivo local indisponivel");
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: isImage(item.file)
          ? Container(
              key: ValueKey(file.path),
              color: Colors.black,
              child: SizedBox.expand(
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                ),
              ),
            )
          : controller != null && controller!.value.isInitialized
          ? FittedBox(
              key: ValueKey(file.path),
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.size.width,
                height: controller!.value.size.height,
                child: VideoPlayer(controller!),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

class _PlayerMessage extends StatelessWidget {
  final String message;

  const _PlayerMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
