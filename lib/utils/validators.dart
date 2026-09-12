class Validators {
  /// Checks if the input is a valid email format
  static bool isEmail(String input) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(input.trim());
  }

  /// Checks if the input is a valid password (8-20 characters)
  static bool isPassword(String input) {
    final passwordRegex = RegExp(r'^.{8,20}$');
    return passwordRegex.hasMatch(input);
  }

  /// Checks if input is valid phone number in international format (+ country code + 10-15 digits)
  static bool isPhone(String input) {
    final cleanedPhone = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final phoneRegex = RegExp(r'^\+[1-9]\d{9,14}$');
    return phoneRegex.hasMatch(cleanedPhone);
  }

  /// Checks if input is a valid URL
  static bool isUrl(String input) {
    final urlRegex = RegExp(
      r'^(https?:\/\/)?([\w\d\-_]+\.)+[\w\d\-_]+(\/.*)?$',
      caseSensitive: false,
    );
    return urlRegex.hasMatch(input.trim());
  }

  /// Checks if input is numeric OTP of exact length
  static bool isOtp(String input, {int length = 4}) {
    final otpRegex = RegExp('^\\d{$length}\$');
    return otpRegex.hasMatch(input.trim());
  }

  /// Checks if trimmed text has minimum length
  static bool isNonEmptyText(String input, {int minLength = 1}) {
    return input.trim().length >= minLength;
  }
}

