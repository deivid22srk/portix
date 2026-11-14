import 'game.dart';
import 'parsing.dart';

class GamePort {
  const GamePort({
    required this.id,
    required this.portKey,
    required this.platformName,
    required this.platformSlug,
    this.project,
    this.source,
    this.url,
    this.dataUrl,
    this.developer,
    this.version,
    this.lastUpdate,
    this.dateAdded,
    this.needsGameFiles = false,
    this.needsGameFilesNote,
    this.works,
    this.controllerSupport,
    this.notes,
    this.visits = 0,
  });

  final String id;
  final String portKey;
  final String platformName;
  final String platformSlug;
  final String? project;
  final String? source;
  final String? url;
  final String? dataUrl;
  final String? developer;
  final String? version;
  final DateTime? lastUpdate;
  final DateTime? dateAdded;
  final bool needsGameFiles;
  final String? needsGameFilesNote;
  final String? works;
  final String? controllerSupport;
  final String? notes;
  final int visits;

  bool get isFree {
    final String label = (source ?? '').toLowerCase();
    return label.startsWith('free') || label.startsWith('mirror');
  }

  factory GamePort.fromMap(Map<String, dynamic> map) => GamePort(
        id: asTextOr(map['id'], ''),
        portKey: asTextOr(map['port_key'], ''),
        platformName: asTextOr(map['platform_name'], '—'),
        platformSlug: asTextOr(map['platform_slug'], ''),
        project: asText(map['project']),
        source: asText(map['source']),
        url: asText(map['url']),
        dataUrl: asText(map['data_url']),
        developer: asText(map['developer']),
        version: asText(map['version']),
        lastUpdate: asDate(map['last_update']),
        dateAdded: asDate(map['date_added']),
        needsGameFiles: map['needs_game_files'] == true,
        needsGameFilesNote: asText(map['needs_game_files_note']),
        works: asText(map['works']),
        controllerSupport: asText(map['controller_support']),
        notes: asText(map['notes']),
        visits: asInt(map['visits']),
      );
}

class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.body,
    required this.author,
    this.createdAt,
  });

  final String id;
  final int rating;
  final String body;
  final String author;
  final DateTime? createdAt;

  factory Review.fromMap(Map<String, dynamic> map) => Review(
        id: asTextOr(map['id'], ''),
        rating: asInt(map['rating']),
        body: asTextOr(map['body'], ''),
        author: asTextOr(map['author'], 'Jogador'),
        createdAt: asDate(map['created_at']),
      );
}

class GameDetail {
  const GameDetail({
    required this.game,
    this.ports = const <GamePort>[],
    this.reviews = const <Review>[],
    this.related = const <Game>[],
  });

  final Game game;
  final List<GamePort> ports;
  final List<Review> reviews;
  final List<Game> related;

  GamePort? get primaryPort {
    for (final GamePort port in ports) {
      if (port.url != null) {
        return port;
      }
    }
    return ports.isEmpty ? null : ports.first;
  }

  factory GameDetail.fromMap(Map<String, dynamic> map) {
    final Map<String, dynamic> game = asMap(map['game']);
    if (game.isEmpty) {
      throw const FormatException('detalhe sem jogo');
    }
    return GameDetail(
      game: Game.fromMap(game),
      ports: asMapList(map['ports']).map(GamePort.fromMap).toList(growable: false),
      reviews: asMapList(map['reviews']).map(Review.fromMap).toList(growable: false),
      related: asMapList(map['related']).map(Game.fromMap).toList(growable: false),
    );
  }
}
