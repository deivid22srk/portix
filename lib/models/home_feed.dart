import 'game.dart';
import 'parsing.dart';

class PlatformInfo {
  const PlatformInfo({
    required this.slug,
    required this.name,
    required this.kind,
    required this.portCount,
  });

  final String slug;
  final String name;
  final String kind;
  final int portCount;

  bool get isSecondary => kind == 'other' || kind == 'multi';

  factory PlatformInfo.fromMap(Map<String, dynamic> map) => PlatformInfo(
        slug: asTextOr(map['slug'], ''),
        name: asTextOr(map['name'], '—'),
        kind: asTextOr(map['kind'], 'console'),
        portCount: asInt(map['port_count']),
      );
}

class GenreInfo {
  const GenreInfo({required this.name, required this.gameCount});

  final String name;
  final int gameCount;

  factory GenreInfo.fromMap(Map<String, dynamic> map) => GenreInfo(
        name: asTextOr(map['name'], '—'),
        gameCount: asInt(map['game_count']),
      );
}

class CatalogStats {
  const CatalogStats({this.games = 0, this.ports = 0, this.platforms = 0});

  final int games;
  final int ports;
  final int platforms;

  factory CatalogStats.fromMap(Map<String, dynamic> map) => CatalogStats(
        games: asInt(map['games']),
        ports: asInt(map['ports']),
        platforms: asInt(map['platforms']),
      );
}

// Facetas usadas pelos filtros de busca. Separadas do feed para permitir
// abrir a busca sem depender do carregamento completo da home.
class CatalogFacets {
  const CatalogFacets({
    this.platforms = const <PlatformInfo>[],
    this.genres = const <GenreInfo>[],
  });

  final List<PlatformInfo> platforms;
  final List<GenreInfo> genres;

  static const CatalogFacets empty = CatalogFacets();

  factory CatalogFacets.fromMap(Map<String, dynamic> map) => CatalogFacets(
        platforms: asMapList(map['platforms'])
            .map(PlatformInfo.fromMap)
            .toList(growable: false),
        genres: asMapList(map['genres']).map(GenreInfo.fromMap).toList(growable: false),
      );
}

class HomeFeed {
  const HomeFeed({
    this.trending = const <Game>[],
    this.recent = const <Game>[],
    this.topRated = const <Game>[],
    this.free = const <Game>[],
    this.classics = const <Game>[],
    this.platforms = const <PlatformInfo>[],
    this.genres = const <GenreInfo>[],
    this.stats = const CatalogStats(),
  });

  final List<Game> trending;
  final List<Game> recent;
  final List<Game> topRated;
  final List<Game> free;
  final List<Game> classics;
  final List<PlatformInfo> platforms;
  final List<GenreInfo> genres;
  final CatalogStats stats;

  bool get isEmpty =>
      trending.isEmpty &&
      recent.isEmpty &&
      topRated.isEmpty &&
      free.isEmpty &&
      classics.isEmpty;

  /// Lista de destaque para o carrossel: prioriza populares e completa com
  /// recentes, sem repetir jogos.
  List<Game> get highlights {
    final List<Game> result = <Game>[];
    final Set<String> seen = <String>{};
    for (final List<Game> source in <List<Game>>[trending, recent, topRated]) {
      for (final Game game in source) {
        if (seen.add(game.id)) {
          result.add(game);
        }
        if (result.length >= 6) {
          return result;
        }
      }
    }
    return result;
  }

  factory HomeFeed.fromMap(Map<String, dynamic> map) {
    List<Game> games(String key) =>
        asMapList(map[key]).map(Game.fromMap).toList(growable: false);
    return HomeFeed(
      trending: games('trending'),
      recent: games('recent'),
      topRated: games('top_rated'),
      free: games('free'),
      classics: games('classics'),
      platforms: asMapList(map['platforms'])
          .map(PlatformInfo.fromMap)
          .toList(growable: false),
      genres: asMapList(map['genres']).map(GenreInfo.fromMap).toList(growable: false),
      stats: CatalogStats.fromMap(asMap(map['stats'])),
    );
  }
}
