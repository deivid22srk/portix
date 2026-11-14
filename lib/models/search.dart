import 'game.dart';

class SearchFilters {
  const SearchFilters({
    this.platform,
    this.genre,
    this.freeOnly = false,
    this.needsRom = false,
    this.sort = 'trending',
  });

  final String? platform;
  final String? genre;
  final bool freeOnly;
  final bool needsRom;
  final String sort;

  bool get isDefault =>
      platform == null && genre == null && !freeOnly && !needsRom && sort == 'trending';

  int get activeCount =>
      (platform == null ? 0 : 1) +
      (genre == null ? 0 : 1) +
      (freeOnly ? 1 : 0) +
      (needsRom ? 1 : 0) +
      (sort == 'trending' ? 0 : 1);

  SearchFilters copyWith({
    String? platform,
    String? genre,
    bool? freeOnly,
    bool? needsRom,
    String? sort,
    bool clearPlatform = false,
    bool clearGenre = false,
  }) =>
      SearchFilters(
        platform: clearPlatform ? null : (platform ?? this.platform),
        genre: clearGenre ? null : (genre ?? this.genre),
        freeOnly: freeOnly ?? this.freeOnly,
        needsRom: needsRom ?? this.needsRom,
        sort: sort ?? this.sort,
      );
}

class SearchRequest {
  const SearchRequest({
    this.query = '',
    this.filters = const SearchFilters(),
    this.offset = 0,
    this.limit = 24,
  });

  final String query;
  final SearchFilters filters;
  final int offset;
  final int limit;
}

class SearchPayload {
  const SearchPayload({this.items = const <Game>[], this.total = 0});

  final List<Game> items;
  final int total;
}
