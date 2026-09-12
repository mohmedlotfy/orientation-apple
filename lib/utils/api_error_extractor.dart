import 'package:dio/dio.dart';

/// Error extraction utility to return user-friendly error messages from API error payloads.
class ApiErrorExtractor {
  ApiErrorExtractor._();

  /// Extracts a human-readable error message from an exception or error payload.
  static String getErrorMessage(dynamic error, {String defaultMessage = 'An unexpected error occurred. Please try again.'}) {
    if (error == null) return defaultMessage;

    if (error is DioException) {
      return _extractFromDioException(error, defaultMessage);
    }

    if (error is String) {
      return error.isNotEmpty ? error : defaultMessage;
    }

    if (error is Map) {
      return _extractFromMap(error) ?? defaultMessage;
    }

    return error.toString().isNotEmpty ? error.toString() : defaultMessage;
  }

  static String _extractFromDioException(DioException dioError, String fallback) {
    switch (dioError.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Unable to connect to the server. Please check your network.';
      case DioExceptionType.badResponse:
        final data = dioError.response?.data;
        if (data is Map) {
          final extracted = _extractFromMap(data);
          if (extracted != null && extracted.isNotEmpty) {
            return extracted;
          }
        } else if (data is String && data.isNotEmpty) {
          return data;
        }

        final statusCode = dioError.response?.statusCode;
        if (statusCode != null) {
          if (statusCode == 401) return 'Session expired. Please log in again.';
          if (statusCode == 403) return 'You do not have permission to perform this action.';
          if (statusCode == 404) return 'Requested resource was not found.';
          if (statusCode >= 500) return 'Server error. Please try again later.';
        }
        return fallback;
      case DioExceptionType.cancel:
        return 'Request was cancelled.';
      default:
        return fallback;
    }
  }

  static String? _extractFromMap(Map data) {
    // NestJS standard format: { statusCode: 400, message: "...", error: "Bad Request" }
    // Or message can be an array of validation errors: { message: ["email must be an email"] }
    final message = data['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    } else if (message is List && message.isNotEmpty) {
      return message.map((e) => e.toString()).join('\n');
    }

    final error = data['error'];
    if (error is String && error.isNotEmpty) {
      return error;
    }

    final errorMsg = data['errorMessage'] ?? data['msg'] ?? data['detail'];
    if (errorMsg is String && errorMsg.isNotEmpty) {
      return errorMsg;
    }

    return null;
  }
}
