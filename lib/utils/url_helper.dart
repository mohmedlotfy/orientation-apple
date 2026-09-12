import '../config/api_config.dart';

/// Helper utility for normalizing and resolving media file URLs.
class UrlHelper {
  UrlHelper._();

  /// Resolves a file path to an absolute URL.
  /// - If [path] is null or empty, returns an empty string.
  /// - If [path] starts with 'http://' or 'https://', returns as-is.
  /// - Otherwise, prepends the base CDN/Server URL.
  static String getFileUrl(String? path) {
    if (path == null || path.trim().isEmpty) {
      return '';
    }

    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    // Determine base host (removing /api/v1 suffix if present)
    var base = ApiConfig.baseUrl;
    if (base.endsWith('/api/v1')) {
      base = base.substring(0, base.length - '/api/v1'.length);
    } else if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    final normalizedPath = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '$base$normalizedPath';
  }
}
