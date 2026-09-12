import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/api_config.dart';

/// A custom subscription unlock dialog that displays `assets/images/unlock.png`
/// with transparent clickable overlays positioned directly above the
/// "Go to Website" and "CANCEL / MAYBE LATER" visual buttons.
class SubscriptionUnlockDialog extends StatelessWidget {
  final String subscribeUrl;

  const SubscriptionUnlockDialog({
    super.key,
    this.subscribeUrl = ApiConfig.checkoutUrl,
  });

  /// Convenient helper to present the [SubscriptionUnlockDialog].
  static Future<void> show(
    BuildContext context, {
    String subscribeUrl = ApiConfig.checkoutUrl,
    bool barrierDismissible = true,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (context) => SubscriptionUnlockDialog(
        subscribeUrl: subscribeUrl,
      ),
    );
  }

  Future<void> _launchWebsite(BuildContext context) async {
    final Uri uri = Uri.parse(subscribeUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching subscribe URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1024 x 1536 (Aspect ratio = 2 / 3)
    const double imageAspectRatio = 1024 / 1536;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          child: AspectRatio(
            aspectRatio: imageAspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // 1. Full unlock graphic
                      Image.asset(
                        'assets/images/unlock.png',
                        fit: BoxFit.cover,
                        width: w,
                        height: h,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: const Color(0xFF141414),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.all(24),
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  color: Colors.white70,
                                  size: 48,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Subscription Required',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                      // 2. "Go to Website" clickable overlay
                      // Placed exactly over the visual red button (minY: 1247, maxY: 1365 in 1536h)
                      Positioned(
                        top: h * 0.812,
                        left: w * 0.145,
                        right: w * 0.145,
                        height: h * 0.078,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(w * 0.04),
                            splashColor: const Color(0x40FFFFFF), // 25% white
                            highlightColor: const Color(0x1FFFFFFF), // 12% white
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _launchWebsite(context);
                            },
                          ),
                        ),
                      ),

                      // 3. "CANCEL / MAYBE LATER" clickable overlay
                      // Placed exactly over the secondary text button (Y: ~1410-1431 in 1536h)
                      Positioned(
                        top: h * 0.902,
                        left: w * 0.20,
                        right: w * 0.20,
                        height: h * 0.052,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            splashColor: const Color(0x26FFFFFF), // 15% white
                            highlightColor: const Color(0x14FFFFFF), // 8% white
                            onTap: () {
                              Navigator.of(context).pop();
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
