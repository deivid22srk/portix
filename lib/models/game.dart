import 'parsing.dart';

class Game {
  const Game({
    required this.id,
    required this.slug,
    required this.title,
    this.year,
    this.genre,
    this.coverUrl,
    this.developer,
    this.description = '',
    this.platforms = const <String>[],
    this.portCount = 0,
    this.visitCount = 0,
    this.downloadCount = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.isFree = false,
    this.needsRom = false,
    this.releasedOn,
  });

  final String id;
  final String slug;
  final String title;
  final int? year;
  final String? genre;
  final String? coverUrl;
  final String? developer;
  final String description;
  final List<String> platforms;
  final int portCount;
  final int visitCount;
  final int downloadCount;
  final double rating;
  final int ratingCount;
  final bool isFree;
  final bool needsRom;
  final DateTime? releasedOn;

  bool get hasRating => ratingCount > 0 && rating > 0;
  String get primaryPlatform => platforms.isEmpty ? '' : platforms.first;

  factory Game.fromMap(Map<String, dynamic> map) {
    final int? year = map['year'] == null ? null : asInt(map['year']);
    return Game(
      id: asText(map['id']) ?? asText(map['slug']) ?? '',
      slug: asText(map['slug']) ?? '',
      title: asTextOr(map['title'], 'Sem título'),
      year: year == 0 ? null : year,
      genre: asText(map['genre']),
      coverUrl: asText(map['cover_url']),
      developer: asText(map['developer']),
      description: asTextOr(map['description'], ''),
      platforms: asStringList(map['platforms']),
      portCount: asInt(map['port_count']),
      visitCount: asInt(map['visit_count']),
      downloadCount: asInt(map['download_count']),
      rating: asDouble(map['rating_avg']),
      ratingCount: asInt(map['rating_count']),
      isFree: map['is_free'] == true,
      needsRom: map['needs_rom'] == true,
      releasedOn: asDate(map['released_on']),
    );
  }
}
