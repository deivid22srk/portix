import '../models/collections.dart';
import '../models/compat_report.dart';
import '../models/game_detail.dart';
import '../models/home_feed.dart';
import '../models/news.dart';
import '../models/profile.dart';
import '../models/search.dart';

abstract class CatalogRepository {
  HomeFeed? readCachedHome();

  Future<HomeFeed> fetchHome();

  Future<CatalogFacets> fetchFacets();

  Future<GameDetail> fetchGame(String slug);

  Future<SearchPayload> search(SearchRequest request);

  Future<NewsPayload> fetchNews({int offset = 0, int limit = 20});

  Future<List<CompatReport>> fetchCompatReports(String gameId);

  Future<UserProfile> fetchProfile();

  Future<void> updateProfile({String? displayName, String? coverUrl});

  Future<Collections> fetchCollections();

  Future<bool> toggleFavorite(String gameId);

  Future<bool> toggleLibrary(String gameId);

  Future<void> addToLibrary(String gameId);

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
  });

  Future<void> syncDownload({
    required String gameId,
    required String? portKey,
    required String status,
    required int progress,
  });
}
