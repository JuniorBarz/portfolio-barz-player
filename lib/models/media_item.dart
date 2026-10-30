class MediaItem {
  final String file;
  final String tipo;
  final int? tempo;
  final String url;

  MediaItem({
    required this.file,
    required this.tipo,
    this.tempo,
    required this.url,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final file = json['file'];
    final tipo = json['tipo'];
    final url = json['url'];

    if (file is! String || file.trim().isEmpty) {
      throw const FormatException("Arquivo invalido");
    }
    if (tipo is! String || (tipo != "imagem" && tipo != "video")) {
      throw const FormatException("Tipo de midia invalido");
    }
    if (url is! String || !url.startsWith("/media/")) {
      throw const FormatException("URL de midia invalida");
    }

    return MediaItem(
      file: file,
      tipo: tipo,
      tempo: json['tempo'] is int ? json['tempo'] : null,
      url: url,
    );
  }
}
