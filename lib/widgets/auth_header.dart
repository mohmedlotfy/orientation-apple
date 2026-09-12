import 'package:flutter/material.dart';
import 'orientation_logo.dart';

class AuthHeader extends StatelessWidget {
  final double? height;
  final double? logoBottom;

  const AuthHeader({
    super.key,
    this.height,
    this.logoBottom,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Responsive default: ~27% of screen height, clamped between 190 and 240 to balance space and fit content
    final effectiveHeight = height ?? (screenHeight * 0.27).clamp(190.0, 240.0);
    final effectiveLogoBottom = logoBottom ?? 20.0;

    return SizedBox(
      height: effectiveHeight,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background image replacing geometric shapes
          Image.asset(
            'assets/images/login_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to black if image is missing
              return Container(color: Colors.black);
            },
          ),
          // Dark gradient overlay to blend into the black screen below
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.4),
                  Colors.black,
                ],
                stops: const [0.25, 0.75, 1.0],
              ),
            ),
          ),
          // Logo centered at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: effectiveLogoBottom,
            child: const Center(
              child: OrientationLogo(),
            ),
          ),
        ],
      ),
    );
  }
}
