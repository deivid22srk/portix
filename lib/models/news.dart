import 'game.dart';
import 'parsing.dart';

/// Item do feed de Notícias: um jogo com o tipo de evento e a data.
class NewsItem {
  const NewsItem({
    required this.game,
    required this.kind,
    this.date,
  });

  final Game game;

  /// 'added' quando o jogo entrou no catálogo, 'updated' quando houve novidade.
  final String kind;
  final DateTime? date;

  bool get isUpdate => kind == 'updated';

  factory NewsItem.fromMap(Map<String, dynamic> map) => NewsItem(
        game: Game.fromMap(map),
        kind: asTextOr(map['kind'], 'added'),
        date: asDate(map['event_on']),
      );
}

class NewsPayload {
  const NewsPayload({this.items = const <NewsItem>[], this.total = 0});

  final List<NewsItem> items;
  final int total;
}
