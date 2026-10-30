// MAIN COM AUTO UPDATE + INTERVALO CONFIGURÁVEL (SEM QUEBRAR SUA LÓGICA)
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'models/media_item.dart';
import 'services/api_service.dart';
import 'services/download_service.dart';
import 'services/playback_service.dart';
import 'services/storage_service.dart';
import 'services/telemetry_service.dart';
import 'player/media_player.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    check();
  }

  Future<void> check() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString("ip");
    final porta = prefs.getString("porta");
    final tv = prefs.getString("tv");

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    if (ip != null && porta != null && tv != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(ip: ip, porta: porta, tv: tv),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConfigScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text("Barz Player")));
  }
}

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final ipController = TextEditingController();
  final portaController = TextEditingController();
  final tvController = TextEditingController();
  final intervaloController = TextEditingController(text: "2");

  bool fullscreen = true;
  bool autostart = true;

  Future<void> salvar() async {
    final ip = ipController.text.trim();
    final porta = portaController.text.trim();
    final tv = tvController.text.trim();
    final intervalo = int.tryParse(intervaloController.text.trim()) ?? 2;

    try {
      buildPlaylistUri(
        host: ip,
        port: parseServicePort(porta),
        channel: tv,
      );
    } on ArgumentError {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Informe host, porta, canal e intervalo válidos"),
        ),
      );
      return;
    }
    if (intervalo < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("O intervalo deve ser positivo")),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("ip", ip);
    await prefs.setString("porta", porta);
    await prefs.setString("tv", tv);

    await prefs.setBool("fullscreen", fullscreen);
    await prefs.setBool("autostart", autostart);
    await prefs.setInt("intervalo", intervalo);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(ip: ip, porta: porta, tv: tv),
      ),
    );
  }

  Future<void> mostrarStorage() async {
    final dir = await StorageService.getTvFolder(
      tvController.text.isEmpty ? "teste" : tvController.text,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Storage do App"),
        content: Text(dir.path),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: dir.path));
              Navigator.pop(context);
            },
            child: const Text("Copiar caminho"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fechar"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    ipController.dispose();
    portaController.dispose();
    tvController.dispose();
    intervaloController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Configurar TV", style: TextStyle(fontSize: 22)),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(labelText: "IP"),
            ),
            TextField(
              controller: portaController,
              decoration: const InputDecoration(labelText: "Porta"),
            ),
            TextField(
              controller: tvController,
              decoration: const InputDecoration(labelText: "Nome da TV"),
            ),
            TextField(
              controller: intervaloController,
              decoration: const InputDecoration(
                labelText: "Atualizar a cada (min)",
              ),
            ),
            CheckboxListTile(
              title: const Text("Tela cheia"),
              value: fullscreen,
              onChanged: (v) => setState(() => fullscreen = v!),
            ),
            CheckboxListTile(
              title: const Text("Auto Boot"),
              value: autostart,
              onChanged: (v) => setState(() => autostart = v!),
            ),
            ElevatedButton(onPressed: salvar, child: const Text("Iniciar")),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: mostrarStorage,
              child: const Text("Ver Storage"),
            ),
          ],
        ),
      ),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  final String ip;
  final String porta;
  final String tv;

  const PlayerScreen({
    super.key,
    required this.ip,
    required this.porta,
    required this.tv,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  List<MediaItem> playlist = [];
  bool loading = true;
  String status = "Iniciando...";
  Directory? folder;
  Timer? autoUpdate;
  bool syncing = false;

  void _sendTelemetry(TelemetrySnapshot snapshot) {
    unawaited(
      TelemetryService.send(
        ip: widget.ip,
        porta: widget.porta,
        tv: widget.tv,
        snapshot: snapshot,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    WakelockPlus.enable();

    final prefs = await SharedPreferences.getInstance();
    final intervalo = prefs.getInt("intervalo") ?? 2;

    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (prefs.getBool("fullscreen") ?? true) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }

    final dir = await StorageService.getTvFolder(widget.tv);

    if (!mounted) return;
    setState(() {
      folder = dir;
      status = "Carregando arquivos locais...";
    });

    final files = dir.listSync().whereType<File>().where((file) {
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : file.path.split(Platform.pathSeparator).last;
      return StorageService.isPlayableMediaFileName(name) &&
          file.existsSync() &&
          file.lengthSync() > 0;
    }).toList();

    playlist = files.map((f) {
      final name = f.uri.pathSegments.isNotEmpty
          ? f.uri.pathSegments.last
          : f.path.split(Platform.pathSeparator).last;
      return MediaItem(
        file: name,
        tipo: name.toLowerCase().endsWith(".mp4") ? "video" : "imagem",
        tempo: 5,
        url: "",
      );
    }).toList();

    if (!mounted) return;
    setState(() {
      loading = false;
    });

    await sync(dir);

    // 🔥 AUTO UPDATE
    autoUpdate = Timer.periodic(Duration(minutes: intervalo), (_) {
      sync(dir);
    });
  }

  Future<void> sync(Directory dir) async {
    if (syncing) return;
    syncing = true;
    setState(() => status = "Buscando API...");

    try {
      final fetchResult = await ApiService.fetchPlaylistWithMetrics(
        widget.ip,
        widget.porta,
        widget.tv,
      );
      final data = fetchResult.items;
      _sendTelemetry(
        TelemetrySnapshot(
          apiLatencyMs: fetchResult.latencyMs,
          downloadStatus: 'ocioso',
          reportLastError: true,
        ),
      );

      await PlaybackService.flushPending(
        dir: dir,
        ip: widget.ip,
        porta: widget.porta,
        tv: widget.tv,
      );

      for (var item in data) {
        final file = StorageService.getFile(dir, item.file);

        if (!file.existsSync() || file.lengthSync() == 0) {
          _sendTelemetry(
            TelemetrySnapshot(downloadStatus: 'baixando ${item.file}'),
          );
          if (mounted) {
            setState(() => status = "Baixando: ${item.file}");
          }
          await DownloadService.downloadFile(
            ApiService.mediaUri(widget.ip, widget.porta, item).toString(),
            file,
            onProgress: (progress) {
              if (!mounted) return;
              final percent = progress.percent;
              final speed = progress.megabytesPerSecond.toStringAsFixed(1);
              final label = percent == null ? "" : " $percent%";
              setState(
                () => status = "Baixando: ${item.file}$label ($speed MB/s)",
              );
            },
          );
          _sendTelemetry(const TelemetrySnapshot(downloadStatus: 'concluído'));
        }
      }

      if (!mounted) return;
      final validPlaylist = data.where((e) {
        return StorageService.hasValidLocalFile(dir, e.file);
      }).toList();

      setState(() {
        playlist = validPlaylist;
        status = validPlaylist.isEmpty ? "Sem midias locais validas" : "Pronto";
      });

      StorageService.cleanOldFiles(dir, data.map((e) => e.file).toList());
    } catch (error, stackTrace) {
      debugPrint("Falha ao sincronizar playlist: $error");
      debugPrintStack(stackTrace: stackTrace);
      _sendTelemetry(
        TelemetrySnapshot(
          downloadStatus: 'erro: ${TelemetryService.sanitizeError(error)}',
          lastError: error.toString(),
        ),
      );
      if (!mounted) return;
      setState(() {
        status = playlist.isEmpty ? "Sem conexao com o servidor" : "Pronto";
      });
    } finally {
      syncing = false;
    }
  }

  @override
  void dispose() {
    autoUpdate?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          if (!loading && folder != null)
            MediaPlayer(
              playlist: playlist,
              folder: folder!,
              onPlaybackStarted: (item, durationSeconds) {
                if (status != "Pronto") {
                  setState(() => status = "Pronto");
                }
                _sendTelemetry(
                  TelemetrySnapshot(
                    currentMedia: item.file,
                    reportLastError: true,
                  ),
                );
                PlaybackService.recordAndFlush(
                  dir: folder!,
                  ip: widget.ip,
                  porta: widget.porta,
                  tv: widget.tv,
                  item: item,
                  durationSeconds: durationSeconds,
                );
              },
              onPlaybackIssue: (message) {
                _sendTelemetry(TelemetrySnapshot(lastError: message));
                if (mounted) {
                  setState(() => status = message);
                }
                Future.delayed(const Duration(seconds: 5), () {
                  if (mounted && folder != null && !syncing) {
                    sync(folder!);
                  }
                });
              },
            ),
          if (loading || status != "Pronto")
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                color: Colors.black87,
                child: Text(
                  status,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
