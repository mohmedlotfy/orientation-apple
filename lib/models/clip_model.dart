class ClipModel {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final String videoUrl;
  final String thumbnail;
  final bool isAsset;
  final String developerName;
  final String developerLogo;
  final String projectName;
  final String projectLogo;
  final int likes;
  final bool isLiked;
  final bool hasWhatsApp;
  final bool? locked;
  final DateTime? createdAt;

  ClipModel({
    required this.id,
    required this.projectId,
    this.title = '',
    this.description = '',
    this.videoUrl = '',
    this.thumbnail = '',
    this.isAsset = false,
    this.developerName = '',
    this.developerLogo = '',
    this.projectName = '',
    this.projectLogo = '',
    this.likes = 0,
    this.isLiked = false,
    this.hasWhatsApp = true,
    this.locked,
    this.createdAt,
  });

  factory ClipModel.fromJson(Map<String, dynamic> json) {
    String projectId = '';
    String projectName = '';
    String projectLogo = '';

    final rawProj = json['projectId'] ?? json['project'];
    if (rawProj != null) {
      if (rawProj is Map) {
        final projMap = Map<String, dynamic>.from(rawProj);
        projectId = projMap['_id']?.toString() ??
            projMap['id']?.toString() ??
            '';
        projectName = projMap['title']?.toString() ??
            projMap['name']?.toString() ??
            projMap['projectName']?.toString() ??
            '';
        projectLogo = projMap['logo']?.toString() ??
            projMap['logoUrl']?.toString() ??
            projMap['projectThumbnailUrl']?.toString() ??
            projMap['thumbnailUrl']?.toString() ??
            projMap['thumbnail']?.toString() ??
            projMap['image']?.toString() ??
            '';
      } else {
        projectId = rawProj.toString();
      }
    }

    // Top-level fallbacks if provided in json directly
    if (projectName.isEmpty) {
      projectName = json['projectName']?.toString() ??
          json['projectTitle']?.toString() ??
          '';
    }
    if (projectLogo.isEmpty) {
      projectLogo = json['projectLogo']?.toString() ??
          json['projectLogoUrl']?.toString() ??
          json['logo']?.toString() ??
          json['logoUrl']?.toString() ??
          '';
    }

    // developerName/developerLogo from populated developerId or developer object
    String developerName = json['developerName']?.toString() ?? '';
    String developerLogo = json['developerLogo']?.toString() ?? '';
    final dev = json['developerId'] ?? json['developer'];
    if (dev is Map) {
      final devMap = Map<String, dynamic>.from(dev);
      if (developerName.isEmpty) {
        developerName = devMap['name']?.toString() ?? devMap['title']?.toString() ?? '';
      }
      if (developerLogo.isEmpty) {
        developerLogo = devMap['logoUrl']?.toString() ??
            devMap['logo']?.toString() ??
            devMap['image']?.toString() ??
            '';
      }
    }

    // Fallbacks between project and developer if one is missing
    if (projectName.isEmpty && developerName.isNotEmpty && developerName != 'User') {
      projectName = developerName;
    }
    if (projectLogo.isEmpty && developerLogo.isNotEmpty) {
      projectLogo = developerLogo;
    }

    final videoUrl = json['videoUrl']?.toString() ??
        json['url']?.toString() ??
        json['video']?.toString() ??
        json['reelUrl']?.toString() ??
        json['video_url']?.toString() ??
        '';

    final thumbnail = json['thumbnail']?.toString() ??
        json['thumbnailUrl']?.toString() ??
        json['reelThumbnailUrl']?.toString() ??
        json['coverUrl']?.toString() ??
        json['poster']?.toString() ??
        '';

    int likes = 0;
    if (json['likes'] != null) {
      likes = int.tryParse(json['likes'].toString()) ?? 0;
    } else if (json['viewCount'] != null) {
      likes = int.tryParse(json['viewCount'].toString()) ?? 0;
    } else if (json['saveCount'] != null) {
      likes = int.tryParse(json['saveCount'].toString()) ?? 0;
    }

    final description = json['description']?.toString() ??
        json['caption']?.toString() ??
        '';

    return ClipModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      projectId: projectId,
      title: json['title']?.toString() ?? '',
      description: description,
      videoUrl: videoUrl,
      thumbnail: thumbnail,
      isAsset: json['isAsset'] == true,
      developerName: developerName.isNotEmpty ? developerName : 'User',
      developerLogo: developerLogo,
      projectName: projectName,
      projectLogo: projectLogo,
      likes: likes,
      isLiked: json['isLiked'] == true,
      hasWhatsApp: json['hasWhatsApp'] != false, // defaults to true unless explicitly false
      locked: json['locked'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }


  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'projectId': projectId,
      'title': title,
      'description': description,
      'videoUrl': videoUrl,
      'thumbnail': thumbnail,
      'isAsset': isAsset,
      'developerName': developerName,
      'developerLogo': developerLogo,
      'projectName': projectName,
      'projectLogo': projectLogo,
      'likes': likes,
      'isLiked': isLiked,
      'hasWhatsApp': hasWhatsApp,
      'locked': locked,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  ClipModel copyWith({
    String? id,
    String? projectId,
    String? title,
    String? description,
    String? videoUrl,
    String? thumbnail,
    bool? isAsset,
    String? developerName,
    String? developerLogo,
    String? projectName,
    String? projectLogo,
    int? likes,
    bool? isLiked,
    bool? hasWhatsApp,
    bool? locked,
    DateTime? createdAt,
  }) {
    return ClipModel(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnail: thumbnail ?? this.thumbnail,
      isAsset: isAsset ?? this.isAsset,
      developerName: developerName ?? this.developerName,
      developerLogo: developerLogo ?? this.developerLogo,
      projectName: projectName ?? this.projectName,
      projectLogo: projectLogo ?? this.projectLogo,
      likes: likes ?? this.likes,
      isLiked: isLiked ?? this.isLiked,
      hasWhatsApp: hasWhatsApp ?? this.hasWhatsApp,
      locked: locked ?? this.locked,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Type alias for Reel / Clip representation
typedef ReelModel = ClipModel;

