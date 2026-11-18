import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cache_store.dart';
import '../core/env.dart';
import '../core/session.dart';
import '../models/app_update.dart';
import '../models/collections.dart';
import '../models/compat_report.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import '../models/home_feed.dart';
import '../models/news.dart';
import '../models/parsing.dart';
import '../models/profile.dart';
import '../models/public_profile.dart';
import '../models/search.dart';
import '../models/user_result.dart';
import 'catalog_repository.dart';

class SupabaseCatalogRepository
    implements CatalogRepository, HomeFeedAlgorithmRepository {
  SupabaseCatalogRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CacheStore _cache;

  /// Último payload bom da RPC NOVA (`get_home_feed`) — o cache preferido.
  ///
  /// Chave ESTÁVEL por sessão/instalação (não por seed): o seed só rege a
  /// ORDENAÇÃO do feed, não a identidade do cache. Uma chave por seed falharia
  /// o stale-while-revalidate ao reabrir o app (seed nova ⇒ cache vazio ⇒ tela
  /// em branco à espera da rede).
  static const String _homeFeedCacheKey = 'home_feed_v2';

  /// Cache do payload legado (`home_feed`), usado só no fallback.
  static const String _homeCacheKey = 'home_feed';

  @override
  HomeFeed? readCachedHome() {
    final Map<String, dynamic>? fresh = _cache.readMap(_homeFeedCacheKey);
    final Map<String, dynamic>? raw = fresh ?? _cache.readMap(_homeCacheKey);
    if (raw == null) {
      return null;
    }
    try {
      return HomeFeed.fromMap(raw);
    } on Object {
      // Cache corrompido é descartado silenciosamente; a rede assume.
      return null;
    }
  }

  /// RPC legada `home_feed`: fallback do feed quando o algoritmo novo falha.
  @override
  Future<HomeFeed> fetchHome() async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('home_feed', params: <String, dynamic>{'p_limit': 10}),
    );
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      throw const AppFailure(FailureKind.server);
    }
    await _cache.writeMap(_homeCacheKey, map);
    return HomeFeed.fromMap(map);
  }

  /// RPC nova, SEM cascata: a cascata (nova → legada → cache → erro) é
  /// orquestrada pelo controller, que preserva o erro ORIGINAL para a tela
  /// distinguir offline de rate limit (429).
  @override
  Future<HomeFeed> fetchHomeFeed({
    required String seed,
    List<String> seen = const <String>[],
    Map<String, dynamic>? cursor,
    List<String>? sections,
  }) async {
    final Map<String, dynamic> map = await _getHomeFeed(
      seed: seed,
      seen: seen,
      cursor: cursor,
      sections: sections,
    );
    // Só o payload bom da RPC nova vira cache preferido.
    await _cache.writeMap(_homeFeedCacheKey, map);
    return HomeFeed.fromMap(map);
  }

  @override
  Future<HomeFeed> loadMoreDiscover({
    required String seed,
    required Map<String, dynamic> cursor,
    List<String> seen = const <String>[],
    List<String>? sections,
  }) async {
    // Paginação não tem fallback: a seção `discover` só existe na RPC nova.
    final Map<String, dynamic> map = await _getHomeFeed(
      seed: seed,
      seen: seen,
      cursor: cursor,
      sections: sections ?? const <String>['discover'],
    );
    return HomeFeed.fromMap(map);
  }

  @override
  Future<void> recordImpressions(
    List<Map<String, dynamic>> items, {
    String? sessionId,
  }) async {
    if (items.isEmpty) {
      return;
    }
    // Opt-out: ausente ou `on` permite; qualquer outro valor desliga.
    if (!feedImpressionsAllowed(_cache.readString(kFeedImpressionsPrefKey))) {
      return;
    }
    final String anon = FeedSession(_cache).anonymousId();
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[
      for (final Map<String, dynamic> item in items)
        if (item['game_id'] != null)
          <String, dynamic>{
            'game_id': item['game_id'],
            'section': item['section'] ?? '',
            if ((item['session_id'] ?? sessionId) != null)
              'session_id': item['session_id'] ?? sessionId,
          },
    ];
    if (payload.isEmpty) {
      return;
    }
    try {
      await _client.rpc(
        'record_feed_impressions',
        params: <String, dynamic>{'p_anon': anon, 'p_items': payload},
      );
    } on Object {
      // Melhor esforço: impressão não é caminho crítico e nunca quebra o feed.
    }
  }

  Future<Map<String, dynamic>> _getHomeFeed({
    required String seed,
    required List<String> seen,
    required Map<String, dynamic>? cursor,
    required List<String>? sections,
  }) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'get_home_feed',
        params: <String, dynamic>{
          'p_seed': seed,
          'p_limit': 12,
          'p_seen': seen,
          'p_cursor': cursor,
          'p_sections': sections,
        },
      ),
    );
    final Map<String, dynamic> map = _map(response);
    if (!map.containsKey('sections')) {
      // Sem `sections` não é um payload válido do algoritmo novo.
      throw const AppFailure(FailureKind.server);
    }
    return map;
  }

  @override
  Future<CatalogFacets> fetchFacets() async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('catalog_facets'),
    );
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      return CatalogFacets.empty;
    }
    return CatalogFacets.fromMap(map);
  }

  @override
  Future<GameDetail> fetchGame(String slug) async {
    final Object? response = await _guard<Object?>(
      () =>
          _client.rpc('game_detail', params: <String, dynamic>{'p_slug': slug}),
    );
    if (response == null) {
      throw const AppFailure(FailureKind.notFound);
    }
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      throw const AppFailure(FailureKind.notFound);
    }
    return GameDetail.fromMap(map);
  }

  @override
  Future<SearchPayload> search(SearchRequest request) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'search_games',
        params: <String, dynamic>{
          'p_query': request.query.isEmpty ? null : request.query,
          'p_platform': request.filters.platform,
          'p_genre': request.filters.genre,
          'p_free_only': request.filters.freeOnly,
          'p_needs_rom': request.filters.needsRom,
          'p_sort': request.filters.sort,
          'p_limit': request.limit,
          'p_offset': request.offset,
        },
      ),
    );
    final Map<String, dynamic> map = _map(response);
    return SearchPayload(
      items: asMapList(map['items']).map(Game.fromMap).toList(growable: false),
      total: asInt(map['total']),
    );
  }

  @override
  Future<NewsPayload> fetchNews({int offset = 0, int limit = 20}) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'news_feed',
        params: <String, dynamic>{'p_limit': limit, 'p_offset': offset},
      ),
    );
    final Map<String, dynamic> map = _map(response);
    final List<NewsItem> items = mapList(map['items'], NewsItem.fromMap);
    return NewsPayload(items: items, total: asInt(map['total']));
  }

  @override
  Future<NewsItem?> fetchNewsArticle(String slug) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'news_article',
        params: <String, dynamic>{'p_slug': slug},
      ),
    );
    if (response is! Map) {
      return null;
    }
    final NewsItem item = NewsItem.fromMap(_map(response));
    return item.slug.isEmpty ? null : item;
  }

  @override
  Future<List<CompatReport>> fetchCompatReports(String gameId) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'game_compat_reports',
        params: <String, dynamic>{'p_game': gameId},
      ),
    );
    if (response is List) {
      // Laço explícito em vez de cadeia: cadeias longas são quebradas de forma
      // diferente entre as versões do formatador (local 3.14.1 x CI 3.14.0).
      final List<CompatReport> reports = <CompatReport>[];
      for (final Object? item in response) {
        if (item is Map) {
          reports.add(CompatReport.fromMap(asMap(item)));
        }
      }
      return reports;
    }
    return const <CompatReport>[];
  }

  @override
  Future<AppUpdate?> fetchLatestUpdate() async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('latest_update'),
    );
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      return null;
    }
    return AppUpdate.fromMap(map);
  }

  @override
  Future<UserProfile> fetchProfile() async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AppFailure(FailureKind.auth);
    }
    final Object? row = await _guard<Object?>(
      () => _client
          .from('profiles')
          .select('id,display_name,cover_url,handle')
          .eq('id', user.id)
          .maybeSingle(),
    );
    final Map<String, dynamic> map = _map(row);
    if (map.isEmpty) {
      return UserProfile(id: user.id);
    }
    return UserProfile.fromMap(map);
  }

  @override
  Future<void> setHandle(String handle) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AppFailure(FailureKind.auth);
    }
    await _guard<Object?>(
      () => _client.rpc(
        'set_handle',
        params: <String, dynamic>{'p_handle': handle},
      ),
    );
  }

  @override
  Future<List<UserResult>> searchUsers(String query) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'search_users',
        params: <String, dynamic>{
          'p_query': query.trim().isEmpty ? null : query.trim(),
          'p_limit': 30,
          'p_offset': 0,
        },
      ),
    );
    final Map<String, dynamic> map = _map(response);
    return mapList(map['items'], UserResult.fromMap);
  }

  @override
  Future<PublicProfile> fetchPublicProfile(String id) async {
    final Object? response = await _guard<Object?>(
      () =>
          _client.rpc('profile_public', params: <String, dynamic>{'p_id': id}),
    );
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      throw const AppFailure(FailureKind.notFound);
    }
    return PublicProfile.fromMap(map);
  }

  @override
  Future<void> updateProfile({String? displayName, String? coverUrl}) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AppFailure(FailureKind.auth);
    }
    await _guard<void>(
      () => _client
          .from('profiles')
          .update(<String, dynamic>{
            if (displayName != null) 'display_name': displayName.trim(),
            if (coverUrl != null)
              'cover_url': coverUrl.trim().isEmpty ? null : coverUrl.trim(),
          })
          .eq('id', user.id),
    );
  }

  @override
  Future<Collections> fetchCollections() async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      // Visitante: não existe coleção no servidor. A sessão anônima automática
      // foi removida de propósito — conta só quando o usuário cria uma.
      return Collections.empty;
    }
    final Object? response = await _guard<Object?>(
      () => _client.rpc('my_collections'),
    );
    final Map<String, dynamic> map = _map(response);
    if (map.isEmpty) {
      return Collections.empty;
    }
    return Collections.fromMap(map);
  }

  @override
  Future<bool> toggleFavorite(String gameId) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      return false;
    }
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'toggle_favorite',
        params: <String, dynamic>{'p_game': gameId},
      ),
    );
    return response == true;
  }

  @override
  Future<bool> toggleLibrary(String gameId) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      return false;
    }
    final Object? response = await _guard<Object?>(
      () => _client.rpc(
        'toggle_library',
        params: <String, dynamic>{'p_game': gameId},
      ),
    );
    return response == true;
  }

  @override
  Future<void> addToLibrary(String gameId) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      return;
    }
    await _guard<void>(
      () => _client.from('library').upsert(<String, dynamic>{
        'user_id': user.id,
        'game_id': gameId,
      }, onConflict: 'user_id,game_id'),
    );
  }

  @override
  Future<void> submitReview({
    required String gameId,
    required int rating,
    required String body,
    required String verdict,
    int? fps,
    String? brand,
    String? model,
    String? soc,
    String? gpu,
    int? ramGb,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AppFailure(FailureKind.auth);
    }
    await _guard<void>(
      () => _client.from('reviews').upsert(<String, dynamic>{
        'game_id': gameId,
        'user_id': user.id,
        'rating': rating,
        'body': body,
        'verdict': verdict,
        'fps': fps,
        'brand': brand,
        'model': model,
        'soc': soc,
        'gpu': gpu,
        'ram_gb': ramGb,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'game_id,user_id'),
    );
  }

  @override
  Future<void> syncDownload({
    required String gameId,
    required String? portKey,
    required String status,
    required int progress,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      return;
    }
    await _guard<void>(
      () => _client.from('downloads').upsert(<String, dynamic>{
        'user_id': user.id,
        'game_id': gameId,
        'port_key': portKey,
        'status': status,
        'progress': progress.clamp(0, 100),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,game_id'),
    );
  }

  Map<String, dynamic> _map(Object? value) => asMap(value);

  /// `429`/`Too Many Requests` do PostgREST vira um estado de UI próprio
  /// ("muitas requisições") em vez de um erro genérico.
  bool _isRateLimited(PostgrestException error) {
    if (error.code == '429') {
      return true;
    }
    final String message = error.message.toLowerCase();
    return message.contains('rate limit') || message.contains('too many');
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST116') {
        throw const AppFailure(FailureKind.notFound);
      }
      if (_isRateLimited(error)) {
        throw AppFailure(FailureKind.rateLimited, detail: error.message);
      }
      throw AppFailure(FailureKind.server, detail: error.message);
    } on AuthException catch (error) {
      throw AppFailure(FailureKind.auth, detail: error.message);
    } on TimeoutException {
      throw const AppFailure(FailureKind.network);
    } on Object catch (error) {
      throw AppFailure(FailureKind.network, detail: error.toString());
    }
  }
}
