/// Model representing a single watch history entry.
class WatchHistoryModel {
  final String id;
  final String userId;
  final String contentId;
  final String contentTitle;
  final String? contentThumbnail;
  final double currentTime; // seconds
  final double duration; // seconds
  final double progressPercentage; // 0-100
  final bool completed;
  final DateTime lastWatchedAt;
  final String? contentType;
  final String? projectId;
  final String? projectTitle;
  final String? episodeUrl;
  final int? season;
  final int? episode;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isCompleted => completed || progressPercentage >= 90.0;

  const WatchHistoryModel({
    required this.id,
    required this.userId,
    required this.contentId,
    required this.contentTitle,
    this.contentThumbnail,
    required this.currentTime,
    required this.duration,
    required this.progressPercentage,
    required this.completed,
    required this.lastWatchedAt,
    this.contentType,
    this.projectId,
    this.projectTitle,
    this.episodeUrl,
    this.season,
    this.episode,
    this.createdAt,
    this.updatedAt,
  });

  factory WatchHistoryModel.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    int? toIntOrNull(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    DateTime? toDate(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    final curTime = toDouble(json['currentTime']);
    final dur = toDouble(json['duration']);
    double prog = toDouble(json['progressPercentage']);
    if (prog == 0.0 && dur > 0) {
      prog = (curTime / dur) * 100.0;
    }

    return WatchHistoryModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? '',
      contentId: json['contentId']?.toString() ?? '',
      contentTitle: json['contentTitle']?.toString() ?? '',
      contentThumbnail: json['contentThumbnail']?.toString() ?? json['thumbnail']?.toString(),
      currentTime: curTime,
      duration: dur,
      progressPercentage: prog,
      completed: json['completed'] == true || prog >= 90.0,
      lastWatchedAt: toDate(json['lastWatchedAt']) ?? DateTime.now(),
      contentType: json['contentType']?.toString() ?? 'episode',
      projectId: json['projectId']?.toString(),
      projectTitle: json['projectTitle']?.toString(),
      episodeUrl: json['episodeUrl']?.toString(),
      season: toIntOrNull(json['season']),
      episode: toIntOrNull(json['episode']),
      createdAt: toDate(json['createdAt']),
      updatedAt: toDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'contentId': contentId,
      'contentTitle': contentTitle,
      'contentThumbnail': contentThumbnail,
      'currentTime': currentTime,
      'duration': duration,
      'progressPercentage': progressPercentage,
      'completed': completed,
      'lastWatchedAt': lastWatchedAt.toIso8601String(),
      'contentType': contentType,
      'projectId': projectId,
      'projectTitle': projectTitle,
      'episodeUrl': episodeUrl,
      'season': season,
      'episode': episode,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

/// Type alias for Watch History Entry
typedef WatchHistoryEntry = WatchHistoryModel;
