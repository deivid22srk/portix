import '../models/collections.dart';
import '../models/game_detail.dart';
import '../models/home_feed.dart';
import '../models/search.dart';

abstract class CatalogRepository {
  HomeFeed? readCachedHome();

  Future<HomeFeed> fetchHome();

  Future<CatalogFacets> fetchFacets();

  Future<GameDetail> fetchGame(String slug);

  Future<SearchPayload> search(SearchRequest request);

  Future<Collections> fetchCollections();

  Future<bool> toggleFavorite(String gameId);

  Future<bool> toggleLibrary(String gameId);

  Future<void> addToLibrary(String gameId);

  Future<void> submitReview({
    required String gameId,
    required int rating,
    required String body,
  });

  Future<void> syncDownload({
    required String gameId,
    required String? portKey,
    required String status,
    required int progress,
  });
}
