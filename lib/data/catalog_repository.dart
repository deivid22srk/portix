import '../models/app_update.dart';
import '../models/collections.dart';
import '../models/compat_report.dart';
import '../models/game_detail.dart';
import '../models/home_feed.dart';
import '../models/news.dart';
import '../models/profile.dart';
import '../models/public_profile.dart';
import '../models/search.dart';
import '../models/user_result.dart';

abstract class CatalogRepository {
  HomeFeed? readCachedHome();

  Future<HomeFeed> fetchHome();

  Future<CatalogFacets> fetchFacets();

  Future<GameDetail> fetchGame(String slug);

  Future<SearchPayload> search(SearchRequest request);

  Future<NewsPayload> fetchNews({int offset = 0, int limit = 20});

  Future<NewsItem?> fetchNewsArticle(String slug);

  Future<List<CompatReport>> fetchCompatReports(String gameId);

  Future<UserProfile> fetchProfile();

  Future<void> setHandle(String handle);

  Future<List<UserResult>> searchUsers(String query);

  Future<PublicProfile> fetchPublicProfile(String id);

  Future<AppUpdate?> fetchLatestUpdate();

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
