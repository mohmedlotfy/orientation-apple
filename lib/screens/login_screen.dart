import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import '../widgets/auth_header.dart';
import '../widgets/custom_text_field.dart';
import '../services/api/auth_api.dart';
import '../utils/validators.dart';
import '../controllers/auth_controller.dart';
import 'forgot_password_screen.dart';
import 'create_account_screen.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthApi _authApi = AuthApi();
  
  bool _isLoading = false;
  bool _isAppleLoading = false;
  String? _errorMessage;
  String? _passwordError;
  // Feature flag: set to true to re-enable Facebook login UI
  final bool _showFacebookLogin = false;

  static const Color brandRed = Color(0xFFE50914);

  @override
  void initState() {
    super.initState();
    _passwordError = null;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    // Validate inputs
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password';
        if (_passwordController.text.isEmpty) {
          _passwordError = 'Password is required';
        }
      });
      return;
    }

    if (!Validators.isEmail(email)) {
      setState(() {
        _errorMessage = 'Please enter a valid email address';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _passwordError = null;
    });

    try {
      await _authApi.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      // Success - navigate to main screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => const MainScreen(),
        ),
      );
    } catch (e) {
      final errStr = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _errorMessage = errStr.isNotEmpty ? errStr : 'Invalid credentials';
        _passwordError = 'Invalid credentials';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAppleLogin() async {
    setState(() {
      _isAppleLoading = true;
      _errorMessage = null;
    });

    try {
      final authController = AuthController();
      final success = await authController.signInWithApple();

      if (!mounted) return;

      if (success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MainScreen(),
          ),
        );
      } else if (authController.errorMessage.value.isNotEmpty) {
        setState(() {
          _errorMessage = authController.errorMessage.value;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAppleLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: keyboardHeight > 0 ? 20 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with background image and logo
                const AuthHeader(),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      // Title
                      const Text(
                        'Log in',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Description
                      Text(
                        'Enter your email and password to start easily following Orientation real estate projects.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Email field
                      CustomTextField(
                        hintText: 'Email',
                        prefixIcon: Icons.email_outlined,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (value) {
                          if (_errorMessage != null) {
                            setState(() {
                              _errorMessage = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      // Password field
                      CustomTextField(
                        hintText: 'Password',
                        prefixIcon: Icons.lock_outline,
                        isPassword: true,
                        controller: _passwordController,
                        errorText: _passwordError,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        onChanged: (val) {
                          if (_passwordError != null) {
                            setState(() {
                              _passwordError = null;
                            });
                          }
                          if (_errorMessage != null) {
                            setState(() {
                              _errorMessage = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      // Forgot password link
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ForgotPasswordScreen(),
                              ),
                            );
                          },
                          child: const Text(
                            'Forgot password',
                            style: TextStyle(
                              color: brandRed,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: brandRed.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: brandRed.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: brandRed, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: brandRed, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isAppleLoading) ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF343434),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF343434).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Social Login Divider
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OR',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Sign in with Apple button (Strict Apple Guideline 4.8 Compliance)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isAppleLoading) ? null : _handleAppleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1C1C1E),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF1C1C1E).withOpacity(0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                              side: BorderSide(color: Colors.white.withOpacity(0.2), width: 1),
                            ),
                            elevation: 0,
                          ),
                          child: _isAppleLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.apple, color: Colors.white, size: 24),
                                    SizedBox(width: 10),
                                    Text(
                                      'Sign in with Apple',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Google & Facebook Social Login Buttons
                      GetX<AuthController>(
                        init: AuthController(),
                        builder: (authController) {
                          final isAnySocialLoading = authController.isGoogleLoading.value || 
                                                     authController.isFacebookLoading.value;
                          return Column(
                            children: [
                              // Google Button
                              _buildSocialButton(
                                title: 'Continue with Google',
                                iconPath: 'assets/icons/google_logo.svg',
                                defaultIcon: Icons.g_mobiledata_rounded,
                                onPressed: (_isLoading || _isAppleLoading || isAnySocialLoading)
                                    ? null 
                                    : () async {
                                        debugPrint('🔘🔘🔘 [LoginScreen] "Continue with Google" button pressed 🔘🔘🔘');
                                        setState(() {
                                          _errorMessage = null;
                                        });
                                        try {
                                          final success = await authController.signInWithGoogle();
                                          if (success && mounted) {
                                            Navigator.pushReplacement(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => const MainScreen(),
                                              ),
                                            );
                                          } else if (mounted && authController.errorMessage.value.isNotEmpty) {
                                            setState(() {
                                              _errorMessage = authController.errorMessage.value;
                                            });
                                          }
                                        } catch (e, stackTrace) {
                                          debugPrint('❌ [LoginScreen] Unhandled Google button error: $e');
                                          debugPrint('❌ [LoginScreen] StackTrace: $stackTrace');
                                        }
                                      },
                                splashLoading: authController.isGoogleLoading.value,
                              ),
                              
                              // Facebook Button (temporarily hidden from UI, auth logic kept intact)
                              if (_showFacebookLogin) ...[
                                const SizedBox(height: 14),
                                _buildSocialButton(
                                  title: 'Continue with Facebook',
                                  iconPath: '',
                                  defaultIcon: Icons.facebook_rounded,
                                  onPressed: (_isLoading || _isAppleLoading || isAnySocialLoading)
                                      ? null 
                                      : () async {
                                          final success = await authController.signInWithFacebook();
                                          if (success && mounted) {
                                            Navigator.pushReplacement(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => const MainScreen(),
                                              ),
                                            );
                                          }
                                        },
                                  splashLoading: authController.isFacebookLoading.value,
                                  isFacebook: true,
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 28),

                      // Create account link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CreateAccountScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'Create an account',
                              style: TextStyle(
                                color: brandRed,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: brandRed,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String title,
    required String iconPath,
    required IconData defaultIcon,
    required VoidCallback? onPressed,
    required bool splashLoading,
    bool isFacebook = false,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1E1E1E), // Dark surface
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF1E1E1E).withOpacity(0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        child: splashLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconPath.isNotEmpty && iconPath.endsWith('.svg'))
                    SvgPicture.asset(iconPath, width: 22, height: 22)
                  else
                    Icon(defaultIcon, color: isFacebook ? const Color(0xFF1877F2) : Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
