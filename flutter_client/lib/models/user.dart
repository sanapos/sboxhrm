class User {
  final String id;
  final String email;
  final String fullName;
  final String role;
  final String? storeId;
  final String? avatarUrl;
  final String? department;
  final String? position;
  final DateTime? createdAt;
  final List<String>? allowedModules;

  User({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.storeId,
    this.avatarUrl,
    this.department,
    this.position,
    this.createdAt,
    this.allowedModules,
  });

  /// Tạo bản sao với allowedModules mới
  User copyWith({List<String>? allowedModules}) {
    return User(
      id: id,
      email: email,
      fullName: fullName,
      role: role,
      storeId: storeId,
      avatarUrl: avatarUrl,
      department: department,
      position: position,
      createdAt: createdAt,
      allowedModules: allowedModules ?? this.allowedModules,
    );
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? json['userName'] ?? '',
      role: json['role'] ?? 'Employee',
      storeId: json['storeId'],
      avatarUrl: json['avatarUrl'],
      department: json['department'],
      position: json['position'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'fullName': fullName,
      'role': role,
      'avatarUrl': avatarUrl,
      'department': department,
      'position': position,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
