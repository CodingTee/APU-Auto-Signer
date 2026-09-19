/// Student data model representing a saved student account.
class Student {
  final int? id;
  final String userId;      // e.g. "tp087051"
  final String token;       // Gzip-compressed attendance token
  final String displayName; // Friendly name for the list
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool isActive;

  Student({
    this.id,
    required this.userId,
    required this.token,
    required this.displayName,
    required this.createdAt,
    this.lastUsedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'token': token,
      'display_name': displayName,
      'created_at': createdAt.toIso8601String(),
      'last_used_at': lastUsedAt?.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Student.fromMap(Map<String, dynamic> map) {
    return Student(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      token: map['token'] as String,
      displayName: map['display_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastUsedAt: map['last_used_at'] != null
          ? DateTime.parse(map['last_used_at'] as String)
          : null,
      isActive: (map['is_active'] as int) == 1,
    );
  }

  Student copyWith({
    int? id,
    String? userId,
    String? token,
    String? displayName,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    bool? isActive,
  }) {
    return Student(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
