import 'package:barz_player/models/media_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses valid image item', () {
    final item = MediaItem.fromJson({
      'file': 'cardapio.jpg',
      'tipo': 'imagem',
      'tempo': 5,
      'url': '/media/sala/cardapio.jpg',
    });

    expect(item.file, 'cardapio.jpg');
    expect(item.tipo, 'imagem');
    expect(item.tempo, 5);
  });

  test('rejects invalid media url', () {
    expect(
      () => MediaItem.fromJson({
        'file': 'cardapio.jpg',
        'tipo': 'imagem',
        'url': 'http://example.com/cardapio.jpg',
      }),
      throwsFormatException,
    );
  });
}
