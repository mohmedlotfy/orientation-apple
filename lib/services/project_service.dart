import '../core/api_client.dart';
import '../models/episode_model.dart';
import 'api/project_api.dart';

class ProjectSummary {
  final String id;
  final String title;
  final String slug;
  final String? location;
  final String? thumbnailUrl;

  ProjectSummary({
    required this.id,
    required this.title,
    required this.slug,
    this.location,
    this.thumbnailUrl,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    return ProjectSummary(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      location: json['location'],
      thumbnailUrl: json['projectThumbnailUrl'],
    );
  }
}

class EpisodeItem {
  final String id;
  final String title;
  final String? videoUrl;
  final String? duration;
  final bool isLocked;
  final int episodeNumber;
  final String? thumbnail;
  final bool isAsset;

  EpisodeItem({
    required this.id,
    required this.title,
    this.videoUrl,
    this.duration,
    required this.isLocked,
    required this.episodeNumber,
    this.thumbnail,
    required this.isAsset,
  });

  factory EpisodeItem.fromJson(Map<String, dynamic> json) {
    int epNum = json['episodeNumber'] ?? 1;
    if (json['episodeOrder'] != null) {
      final orderStr = json['episodeOrder'].toString();
      final orderMatch = RegExp(r'\d+').firstMatch(orderStr);
      if (orderMatch != null) {
        epNum = int.tryParse(orderMatch.group(0) ?? '1') ?? 1;
      }
    }
    // Support 'locked' (backend field), 'isLocked', and free flags
    bool isLocked = true;
    if (json.containsKey('locked')) {
      isLocked = json['locked'] == true;
    } else if (json.containsKey('isLocked')) {
      isLocked = json['isLocked'] == true;
    } else if (json.containsKey('isFree')) {
      isLocked = json['isFree'] != true;
    } else if (json.containsKey('free')) {
      isLocked = json['free'] != true;
    }

    return EpisodeItem(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      videoUrl: json['episodeUrl'] ?? json['videoUrl'],
      duration: json['duration'],
      isLocked: isLocked,
      episodeNumber: epNum,
      thumbnail: json['thumbnail'] ?? json['thumbnailUrl'],
      isAsset: json['isAsset'] ?? false,
    );
  }

  EpisodeModel toEpisodeModel(String projectId) {
    return EpisodeModel(
      id: id,
      projectId: projectId,
      title: title,
      episodeNumber: episodeNumber,
      thumbnail: thumbnail ?? '',
      isAsset: isAsset,
      videoUrl: videoUrl ?? '',
      duration: duration ?? '',
    );
  }
}

class ProjectDetails {
  final String id;
  final String title;
  final String slug;
  final String? location;
  final String? description;
  final String? projectThumbnailUrl;
  final bool hasAccess;
  final List<EpisodeItem> episodes;

  ProjectDetails({
    required this.id,
    required this.title,
    required this.slug,
    this.location,
    this.description,
    this.projectThumbnailUrl,
    required this.hasAccess,
    required this.episodes,
  });

  factory ProjectDetails.fromJson(Map<String, dynamic> json) {
    final episodesList = json['episodes'] as List? ?? [];
    return ProjectDetails(
      id: json['_id'] ?? json['id'] ?? '',
      title: json['title'] ?? '',
      slug: json['slug'] ?? '',
      location: json['location'],
      description: json['description'],
      projectThumbnailUrl: json['projectThumbnailUrl'],
      hasAccess: json['hasAccess'] ?? false,
      episodes: episodesList.map((e) => EpisodeItem.fromJson(e)).toList(),
    );
  }
}

class ProjectService {
  /// GET /projects/free?page=1&limit=10
  /// Pass page and limit as strings to conform to backend DTO query validation requirements.
  static Future<List<ProjectSummary>> getFreeProjects({int page = 1, int limit = 10}) async {
    try {
      final response = await ApiClient.dio.get(
        '/projects/free',
        queryParameters: {'page': page.toString(), 'limit': limit.toString()},
      );

      List data;
      final responseData = response.data;
      if (responseData is List) {
        data = responseData;
      } else if (responseData is Map && responseData['value'] is List) {
        data = responseData['value'] as List;
      } else if (responseData is Map && responseData['items'] is List) {
        data = responseData['items'] as List;
      } else if (responseData is Map && responseData['data'] is List) {
        data = responseData['data'] as List;
      } else {
        data = [];
      }

      return data.map((json) => ProjectSummary.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Error fetching free projects: $e');
      rethrow;
    }
  }

  static Future<ProjectDetails> getProjectDetails(String projectId, {bool forceRefresh = false}) async {
    try {
      final projectApi = ProjectApi();
      final json = await projectApi.getProjectRawJson(projectId, forceRefresh: forceRefresh);
      if (json == null) {
        throw Exception('Project not found for ID $projectId');
      }
      return ProjectDetails.fromJson(json);
    } catch (e) {
      print('Error fetching project details: $e');
      rethrow;
    }
  }
}
