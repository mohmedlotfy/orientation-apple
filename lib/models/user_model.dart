class UserModel {
  final String id;
  final String username;
  final String email;
  final String? phoneNumber;
  final String role;
  final bool isSubscribed;
  final String? subscriptionStatus;
  final String? planName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.phoneNumber,
    required this.role,
    this.isSubscribed = false,
    this.subscriptionStatus,
    this.planName,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Parse subscription fields across backend conventions
    bool isSub = false;
    String? subStatus;
    String? pName;

    // If backend explicitly returns false for subscription, respect it!
    if (json['isSubscribed'] == false || json['hasAccess'] == false) {
      isSub = false;
    } else {
      final sub = json['subscription'];
      if (sub is Map) {
        subStatus = sub['status']?.toString();
        pName = sub['planName']?.toString() ??
            (sub['plan'] is Map ? sub['plan']['name']?.toString() : null);
        final s = subStatus?.toLowerCase();
        if (s == 'active' || s == 'trialing' || s == 'paid' || sub['isActive'] == true || sub['hasAccess'] == true) {
          isSub = true;
        }
      } else if (sub is String && (sub.toLowerCase() == 'active' || sub.toLowerCase() == 'subscribed')) {
        isSub = true;
        subStatus = sub;
      } else if (sub == true) {
        isSub = true;
      }

      if (!isSub) {
        if (json['isSubscribed'] == true ||
            json['hasAccess'] == true ||
            json['hasActivePlan'] == true ||
            json['subscribed'] == true) {
          isSub = true;
        }
        // NOTE: Only use subscriptionStatus, NOT json['status'] which is user account status
        subStatus ??= json['subscriptionStatus']?.toString();
        pName ??= json['planName']?.toString() ??
            (json['plan'] is Map ? json['plan']['name']?.toString() : json['plan']?.toString());
        if (subStatus?.toLowerCase() == 'active' || subStatus?.toLowerCase() == 'trialing') {
          isSub = true;
        }
      }
    }

    return UserModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      username: (json['username'] ?? '') as String,
      email: (json['email'] ?? '') as String,
      phoneNumber: json['phoneNumber']?.toString(),
      role: (json['role'] ?? 'user') as String,
      isSubscribed: isSub,
      subscriptionStatus: subStatus,
      planName: pName,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'phoneNumber': phoneNumber,
      'role': role,
      'isSubscribed': isSubscribed,
      'subscriptionStatus': subscriptionStatus,
      'planName': planName,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class AuthResponse {
  final UserModel user;
  final String accessToken;
  final String refreshToken;

  AuthResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    // Support both old format (token) and new format (accessToken + refreshToken)
    final accessToken = json['accessToken']?.toString() ?? json['token']?.toString() ?? '';
    final refreshToken = json['refreshToken']?.toString() ?? '';
    
    // Parse user object
    UserModel user;
    if (json['user'] != null && json['user'] is Map) {
      user = UserModel.fromJson(json['user'] as Map<String, dynamic>);
    } else {
      // Fallback: construct skeleton UserModel using the id if available
      final id = json['id']?.toString() ?? json['_id']?.toString() ?? '';
      user = UserModel(
        id: id,
        username: '',
        email: '',
        role: 'user',
      );
    }
    
    return AuthResponse(
      user: user,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
  
  // Backward compatibility: get token (returns accessToken)
  String get token => accessToken;
}
