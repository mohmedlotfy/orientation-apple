import 'dart:async';
import 'package:flutter/foundation.dart';

/// Single cache entry in RAM.
class CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  CacheEntry({
    required this.data,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-Memory Request Cache with TTL and In-Flight Request De-duplication.
/// Operates strictly in RAM (no disk persistence) to optimize general browsing routes.
class InMemoryCacheService {
  static final InMemoryCacheService _instance = InMemoryCacheService._internal();
  factory InMemoryCacheService() => _instance;
  InMemoryCacheService._internal();

  final Map<String, CacheEntry<dynamic>> _cache = {};
  final Map<String, Future<dynamic>> _inFlight = {};

  /// Retrieves data from cache or executes [fetcher] with in-flight de-duplication.
  Future<T> getCached<T>({
    required String key,
    required Future<T> Function() fetcher,
    Duration ttl = const Duration(hours: 1),
    bool forceRefresh = false,
  }) async {
    // 1. Check in-memory cache if not forcing refresh
    if (!forceRefresh) {
      final entry = _cache[key];
      if (entry != null && !entry.isExpired) {
        if (entry.data is T) {
          debugPrint('⚡ [RAM Cache HIT] $key');
          return entry.data as T;
        }
      } else if (entry != null && entry.isExpired) {
        _cache.remove(key);
      }
    }

    // 2. Check if identical request is currently in-flight
    if (_inFlight.containsKey(key)) {
      debugPrint('🔁 [In-Flight De-dup] $key (coalescing request)');
      final result = await _inFlight[key]!;
      return result as T;
    }

    // 3. Create new in-flight future
    final Completer<T> completer = Completer<T>();
    _inFlight[key] = completer.future;

    try {
      debugPrint('🌐 [Network Fetch] $key');
      final T data = await fetcher();

      // Store in RAM cache
      _cache[key] = CacheEntry<T>(
        data: data,
        expiresAt: DateTime.now().add(ttl),
      );

      completer.complete(data);
      return data;
    } catch (e) {
      // Do NOT cache on error; allow subsequent requests to retry
      completer.completeError(e);
      rethrow;
    } finally {
      // Always remove from in-flight tracker upon completion
      _inFlight.remove(key);
    }
  }

  /// Sets or updates a cache entry manually.
  void set<T>(String key, T data, {Duration ttl = const Duration(hours: 1)}) {
    _cache[key] = CacheEntry<T>(
      data: data,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  /// Gets a cached item directly without fetching.
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) {
      if (entry.data is T) {
        return entry.data as T;
      }
    }
    return null;
  }

  /// Invalidates a specific key from cache.
  void invalidate(String key) {
    _cache.remove(key);
    debugPrint('🗑️ [Cache Invalidated] $key');
  }

  /// Invalidates all cache entries whose keys start with [prefix].
  void invalidatePrefix(String prefix) {
    final keysToRemove = _cache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keysToRemove) {
      _cache.remove(k);
    }
    debugPrint('🗑️ [Cache Prefix Invalidated] "$prefix" (${keysToRemove.length} keys evicted)');
  }

  /// Wipes entire RAM cache (e.g. on Login, Logout, or Subscription change).
  void clearAllCache() {
    final count = _cache.length;
    _cache.clear();
    _inFlight.clear();
    debugPrint('🧹 [Cache Cleared] All $count in-memory cache entries wiped.');
  }
}
