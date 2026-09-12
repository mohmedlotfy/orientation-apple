import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';
import 'services/cache_service.dart';
import 'services/clip_service.dart';
import 'services/api/improved_clip_api.dart';
import 'services/api/project_api.dart';
import 'package:screen_protector/screen_protector.dart';
import 'core/api_client.dart';
import 'core/auth_interceptor.dart';
import 'screens/login_screen.dart';
import 'services/in_memory_cache_service.dart';
import 'services/subscription_service.dart';

import 'controllers/auth_controller.dart';

final RouteObserver<ModalRoute<void>> routeObserver = RouteObserver<ModalRoute<void>>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.presentError(details);
    }
    if (kReleaseMode) {
      FlutterError.dumpErrorToConsole(details);
    }
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await _initializeApp();
    runApp(const OrientationApp());
  }, (error, stack) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('Zone error: $error\n$stack');
    }
  });
}

Future<void> _initializeApp() async {
  ApiClient.init();
  AuthInterceptor.onAuthFailure = () {
    try {
      if (Get.isRegistered<AuthController>()) {
        Get.find<AuthController>().currentUser.value = null;
      }
    } catch (_) {}
  };
  try {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  } catch (_) {}

  try {
    final cacheService = CacheService();
    await cacheService.clearReelsCache();
    if (kDebugMode) debugPrint('Video caches cleared on app start');
  } catch (e) {
    if (kDebugMode) debugPrint('Error clearing video caches: $e');
  }

  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
    if (kDebugMode) debugPrint('Notification service initialized');
  } catch (e) {
    if (kDebugMode) debugPrint('Notification init error (non-fatal): $e');
  }

  try {
    Get.put(AuthController(), permanent: true);
    Get.put(ImprovedClipApi(), permanent: true);
    Get.put(ProjectApi(), permanent: true);
    Get.put(
      ClipService(
        clipApi: Get.find<ImprovedClipApi>(),
        projectApi: Get.find<ProjectApi>(),
      ),
      permanent: true,
    );
  } catch (e) {
    if (kDebugMode) debugPrint('Get.put init error (non-fatal): $e');
  }
}

class OrientationApp extends StatefulWidget {
  const OrientationApp({super.key});

  @override
  State<OrientationApp> createState() => _OrientationAppState();
}

class _OrientationAppState extends State<OrientationApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initScreenProtector();
  }

  Future<void> _initScreenProtector() async {
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageOn();
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      if (kDebugMode) debugPrint('Screen protector initialized successfully');
    } catch (e) {
      if (kDebugMode) debugPrint('Error initializing screen protector: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      ScreenProtector.preventScreenshotOff();
      ScreenProtector.protectDataLeakageOff();
      ScreenProtector.protectDataLeakageWithColorOff();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // User returned to app (e.g. from external web checkout)
      try {
        SubscriptionService().getCurrentSubscription();
        InMemoryCacheService().clearAllCache();
        if (kDebugMode) debugPrint('🔄 [Lifecycle Resumed] Cleared cache and refreshed subscription status.');
      } catch (_) {}
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      try {
        if (Get.isRegistered<ClipService>()) {
          Get.find<ClipService>().flush();
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Orientation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE50914),
          secondary: const Color(0xFFE50914),
          surface: Colors.black,
        ),
      ),
      navigatorObservers: [routeObserver],
      home: const SplashScreen(),
    );
  }
}
