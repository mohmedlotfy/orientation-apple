/// ---------------------------------------------------------------------------
/// ApiConfig — Single source of truth for all API configuration.
///
/// ## How to run with a custom URL (--dart-define):
///
///   # Production (default — no flag needed)
///   flutter run
///
///   # Override to a local dev server
///   flutter run --dart-define=BASE_URL=http://localhost:3000
///
///   # Override to staging
///   flutter run --dart-define=BASE_URL=https://staging.orientationapps.com
///
///   # Build release with production URL explicitly
///   flutter build apk --dart-define=BASE_URL=https://api.orientationapps.com/api/v1
///
/// The value is baked in at compile time — no runtime file reads needed.
/// ---------------------------------------------------------------------------
class ApiConfig {
  ApiConfig._(); // prevent instantiation

  // ── Base URLs ──────────────────────────────────────────────────────────────

  /// Production base URL (active live backend).
  static const String productionUrl = 'https://api.orientationapps.com/api/v1';

  /// Local development URL (Android emulator uses 10.0.2.2 instead of localhost).
  static const String devUrl = 'http://10.0.2.2:3000';

  /// Staging URL (update when you have one).
  static const String stagingUrl = 'https://staging.orientationapps.com';

  /// Web checkout / subscription URL (used for subscription purchases).
  static const String checkoutUrl = 'https://orientationapps.com/checkout';

  // ── Active URL — resolved at compile time via --dart-define ───────────────
  //
  // `const String.fromEnvironment` reads the value passed with
  // `--dart-define=BASE_URL=...` at build/run time.
  // Falls back to [productionUrl] when the flag is absent.
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: productionUrl,
  );

  // ── Timeout settings ──────────────────────────────────────────────────────

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
  static const Duration sendTimeout = Duration(seconds: 15);

  // ── Common headers ────────────────────────────────────────────────────────

  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Connection': 'keep-alive',
  };
}
