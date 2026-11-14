import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/cache_store.dart';
import '../core/env.dart';
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
  Future<NewsPayload> fetchNews({int offset = 0, int limit = 20}) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('news_feed', params: <String, dynamic>{
        'p_limit': limit,
        'p_offset': offset,
      }),
    );
    final Map<String, dynamic> map = _map(response);
    return NewsPayload(
      items: asMapList(map['items']).map(NewsItem.fromMap).toList(growable: false),
      total: asInt(map['total']),
    );
  }

  @override
  Future<List<CompatReport>> fetchCompatReports(String gameId) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('game_compat_reports', params: <String, dynamic>{
        'p_game': gameId,
      }),
    );
    if (response is List) {
      return response
          .whereType<Map>()
          .map((Map item) => CompatReport.fromMap(asMap(item)))
          .toList(growable: false);
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
      () => _client.rpc('set_handle', params: <String, dynamic>{'p_handle': handle}),
    );
  }

  @override
  Future<List<UserResult>> searchUsers(String query) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('search_users', params: <String, dynamic>{
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_limit': 30,
        'p_offset': 0,
      }),
    );
    final Map<String, dynamic> map = _map(response);
    return asMapList(map['items'])
        .map(UserResult.fromMap)
        .toList(growable: false);
  }

  @override
  Future<PublicProfile> fetchPublicProfile(String id) async {
    final Object? response = await _guard<Object?>(
      () => _client.rpc('profile_public', params: <String, dynamic>{'p_id': id}),
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
      () => _client.from('profiles').update(<String, dynamic>{
        if (displayName != null) 'display_name': displayName.trim(),
        if (coverUrl != null) 'cover_url': coverUrl.trim().isEmpty ? null : coverUrl.trim(),
      }).eq('id', user.id),
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
      () => _client.from('reviews').upsert(
        <String, dynamic>{
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
