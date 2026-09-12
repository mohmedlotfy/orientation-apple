import '../core/api_client.dart';
import '../models/news_model.dart';
import 'in_memory_cache_service.dart';

/// News Service handling all /news NestJS routes with 1-hour in-memory TTL.
class NewsService {
  final InMemoryCacheService _cache = InMemoryCacheService();

  List<NewsModel> _parseList(dynamic data) {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map) {
      list = (data['data'] as List<dynamic>?) ??
          (data['news'] as List<dynamic>?) ??
          (data['items'] as List<dynamic>?) ??
          [];
    }
    return list.map((item) {
      if (item is Map) {
        return NewsModel.fromJson(Map<String, dynamic>.from(item));
      }
      return NewsModel(
        id: '',
        projectId: '',
        title: '',
        image: '',
        date: DateTime.now(),
        projectName: '',
      );
    }).toList();
  }

  /// GET /news
  /// Cache key: news:all (TTL: 1 hour)
  Future<List<NewsModel>> getNews({bool forceRefresh = false}) async {
    return _cache.getCached<List<NewsModel>>(
      key: 'news:all',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get('/news');
        return _parseList(response.data);
      },
    );
  }

  /// GET /news/:id
  /// Cache key: news:$id
  Future<NewsModel> getNewsById(String id, {bool forceRefresh = false}) async {
    return _cache.getCached<NewsModel>(
      key: 'news:$id',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get('/news/$id');
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return NewsModel.fromJson(data);
        } else if (data is Map) {
          return NewsModel.fromJson(Map<String, dynamic>.from(data));
        }
        throw Exception('News item $id not found');
      },
    );
  }
}
