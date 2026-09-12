import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';
import '../core/api_client.dart';
import '../models/subscription_plan_model.dart';
import 'in_memory_cache_service.dart';

class UserSubscriptionStatus {
  final bool hasAccess;
  final String? status;
  final String? planName;
  final DateTime? periodEnd;
  final dynamic rawData;

  UserSubscriptionStatus({
    required this.hasAccess,
    this.status,
    this.planName,
    this.periodEnd,
    this.rawData,
  });

  factory UserSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    bool access = false;
    String? statusStr;
    String? pName;
    DateTime? pEnd;

    if (json['hasAccess'] == true ||
        json['isSubscribed'] == true ||
        json['isActive'] == true ||
        json['status'] == 'active' ||
        json['status'] == 'paid' ||
        json['status'] == 'trialing') {
      access = true;
    }

    final sub = json['subscription'] ?? json['data'] ?? json;
    if (sub is Map) {
      statusStr = sub['status']?.toString() ?? json['status']?.toString();
      pName = sub['planName']?.toString() ??
          (sub['plan'] is Map ? sub['plan']['name']?.toString() : null) ??
          json['planName']?.toString();
      final endVal = sub['currentPeriodEnd'] ?? sub['periodEnd'] ?? json['periodEnd'];
      if (endVal != null) {
        pEnd = DateTime.tryParse(endVal.toString());
      }
    }

    return UserSubscriptionStatus(
      hasAccess: access,
      status: statusStr,
      planName: pName,
      periodEnd: pEnd,
      rawData: json,
    );
  }
}

/// Service handling all /subscriptions/* and /subscription-plans NestJS routes.
class SubscriptionService {
  final InMemoryCacheService _cache = InMemoryCacheService();
  static bool? _cachedLocalAccess;

  /// GET /subscription-plans
  /// Cache key: subscription-plans (TTL: 1 hour)
  Future<List<SubscriptionPlanModel>> getPlans({bool forceRefresh = false}) async {
    return _cache.getCached<List<SubscriptionPlanModel>>(
      key: 'subscription-plans',
      forceRefresh: forceRefresh,
      ttl: const Duration(hours: 1),
      fetcher: () async {
        final response = await ApiClient.dio.get('/subscription-plans');
        final data = response.data;
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is Map) {
          list = (data['plans'] as List<dynamic>?) ??
              (data['data'] as List<dynamic>?) ??
              [];
        }

        return list.map((item) {
          if (item is Map) {
            return SubscriptionPlanModel.fromJson(Map<String, dynamic>.from(item));
          }
          return SubscriptionPlanModel.fromJson({});
        }).toList();
      },
    );
  }

  /// GET /subscriptions/me
  /// NO LONG CACHE (User-sensitive entitlement status).
  Future<UserSubscriptionStatus> getCurrentSubscription() async {
    try {
      final response = await ApiClient.dio.get('/subscriptions/me');
      final data = response.data;
      if (data is Map<String, dynamic>) {
        final status = UserSubscriptionStatus.fromJson(data);
        await _saveLocalSubscriptionAccess(status.hasAccess);
        return status;
      } else if (data is Map) {
        final status = UserSubscriptionStatus.fromJson(Map<String, dynamic>.from(data));
        await _saveLocalSubscriptionAccess(status.hasAccess);
        return status;
      }
    } catch (e) {
      debugPrint('⚠️ [SubscriptionService] Error fetching current subscription: $e');
    }

    final localAccess = await getLocalSubscriptionAccess();
    return UserSubscriptionStatus(hasAccess: localAccess);
  }

  /// Checks user subscription access status (static helper).
  static Future<UserSubscriptionStatus> checkMySubscription({bool forceRefresh = false}) async {
    return SubscriptionService().getCurrentSubscription();
  }

  /// Synchronously retrieve current subscription status (0 network calls).
  static UserSubscriptionStatus get currentSubscriptionStatus {
    return UserSubscriptionStatus(hasAccess: _cachedLocalAccess ?? false);
  }

  /// Manually caches user subscription status locally (static helper).
  static Future<void> cacheSubscriptionStatus(UserSubscriptionStatus status) async {
    await SubscriptionService()._saveLocalSubscriptionAccess(status.hasAccess);
  }

  /// Clears in-memory subscription caches (static helper).
  static Future<void> clearSubscriptionCache() async {
    InMemoryCacheService().invalidate('subscription-plans');
    InMemoryCacheService().clearAllCache();
  }

  /// Retrieves the cached local subscription access flag (static helper).
  static Future<UserSubscriptionStatus?> getCachedSubscriptionStatus() async {
    final hasAccess = await SubscriptionService().getLocalSubscriptionAccess();
    return UserSubscriptionStatus(hasAccess: hasAccess);
  }

  /// POST /subscriptions/checkout
  /// Initiates subscription checkout and returns checkout details.
  Future<Map<String, dynamic>?> createCheckoutSession(String planId) async {
    try {
      final response = await ApiClient.dio.post(
        '/subscriptions/checkout',
        data: {'planId': planId},
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
    } catch (e) {
      debugPrint('❌ [SubscriptionService] Checkout session creation failed: $e');
    }
    return null;
  }

  /// Launches the web-delegated checkout flow in the default browser.
  static Future<bool> launchWebCheckout({String? checkoutUrl}) async {
    final targetUrl = checkoutUrl ?? ApiConfig.checkoutUrl;
    final uri = Uri.parse(targetUrl);
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('❌ [SubscriptionService] Could not launch checkout URL: $e');
    }
    return false;
  }

  /// PATCH /subscriptions/cancel
  /// Turns off auto-renew.
  Future<bool> cancelSubscription() async {
    try {
      final response = await ApiClient.dio.patch('/subscriptions/cancel');
      _cache.clearAllCache();
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  /// PATCH /subscriptions/reactivate
  /// Turns auto-renew back on.
  Future<bool> reactivateSubscription() async {
    try {
      final response = await ApiClient.dio.patch('/subscriptions/reactivate');
      _cache.clearAllCache();
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveLocalSubscriptionAccess(bool hasAccess) async {
    _cachedLocalAccess = hasAccess;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_has_subscription_access', hasAccess);
    } catch (_) {}
  }

  Future<bool> getLocalSubscriptionAccess() async {
    if (_cachedLocalAccess != null) return _cachedLocalAccess!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final access = prefs.getBool('user_has_subscription_access') ?? false;
      _cachedLocalAccess = access;
      return access;
    } catch (_) {
      return false;
    }
  }
}
