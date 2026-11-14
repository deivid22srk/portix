import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cache_store.dart';
import '../core/env.dart';
import '../models/collections.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import '../models/home_feed.dart';
import '../models/parsing.dart';
import '../models/search.dart';
import 'catalog_repository.dart';

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._client, this._cache);

  final SupabaseClient _client;
  final CacheStore _cache;

  static const String _homeCacheKey = 'home_feed';

  @override
  HomeFeed? readCachedHome() {
    final Map<String, dynamic>? raw = _cache.readMap(_homeCacheKey);
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
      () => _client.rpc('game_detail', params: <String, dynamic>{'p_slug': slug}),
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
      () => _client.rpc('search_games', params: <String, dynamic>{
        'p_query': request.query.isEmpty ? null : request.query,
        'p_platform': request.filters.platform,
        'p_genre': request.filters.genre,
        'p_free_only': request.filters.freeOnly,
        'p_needs_rom': request.filters.needsRom,
        'p_sort': request.filters.sort,
        'p_limit': request.limit,
        'p_offset': request.offset,
      }),
    );
    final Map<String, dynamic> map = _map(response);
    return SearchPayload(
      items: asMapList(map['items']).map(Game.fromMap).toList(growable: false),
      total: asInt(map['total']),
    );
  }

  @override
  Future<Collections> fetchCollections() async {
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
    final Object? response = await _guard<Object?>(
      () => _client.rpc('toggle_favorite', params: <String, dynamic>{'p_game': gameId}),
    );
    return response == true;
  }

  @override
  Future<bool> toggleLibrary(String gameId) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('toggle_library', params: <String, dynamic>{'p_game': gameId}),
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
      () => _client.from('library').upsert(
        <String, dynamic>{'user_id': user.id, 'game_id': gameId},
        onConflict: 'user_id,game_id',
      ),
    );
  }

  @override
  Future<void> submitReview({
    required String gameId,
    required int rating,
    required String body,
  }) async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw const AppFailure(FailureKind.auth);
    }
    await _guard<void>(
      () => _client.from('reviews').upsert(
        <String, dynamic>{
          'game_id': gameId,
          'user_id': user.id,
          'rating': rating,
          'body': body,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'game_id,user_id',
      ),
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
      () => _client.from('downloads').upsert(
        <String, dynamic>{
          'user_id': user.id,
          'game_id': gameId,
          'port_key': portKey,
          'status': status,
          'progress': progress.clamp(0, 100),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,game_id',
      ),
    );
  }

  Map<String, dynamic> _map(Object? value) => asMap(value);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == 'PGRST116') {
        throw const AppFailure(FailureKind.notFound);
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
