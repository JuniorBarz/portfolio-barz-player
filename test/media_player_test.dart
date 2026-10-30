import 'package:barz_player/models/media_item.dart';
import 'package:barz_player/player/media_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('image duration uses configured display time', () {
    final item = MediaItem(
      file: 'cartaz.jpg',
      tipo: 'imagem',
      tempo: 7,
      url: '/media/sala/cartaz.jpg',
    );

    expect(playbackDurationSeconds(item), 7);
  });

  test('video duration uses initialized controller metadata', () {
    final item = MediaItem(
      file: 'oferta.mp4',
      tipo: 'video',
      url: '/media/sala/oferta.mp4',
    );

    expect(
      playbackDurationSeconds(item, videoDuration: const Duration(seconds: 42)),
      42,
    );
  });
}
