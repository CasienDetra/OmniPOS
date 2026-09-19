import 'package:mongo_dart/mongo_dart.dart';

import '../core/auth.dart';
import '../core/pagination.dart';

class User {
  const User({
    this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.passwordHash,
    required this.avatar,
    required this.isActive,
    required this.roles,
    required this.createdAt,
    required this.updatedAt,
    this.lastLogin,
  });

  static User fromDocument(Map<String, dynamic> doc) => User(
        id: doc['_id'] as ObjectId?,
        name: doc['name'] as String? ?? '',
        phone: doc['phone'] as String? ?? '',
        email: doc['email'] as String? ?? '',
        passwordHash: doc['password'] as String? ?? '',
        avatar: doc['avatar'] as String?,
        isActive: doc['is_active'] != false,
        roles: [
          for (final role in (doc['roles'] as List? ?? const []))
            if (role is Map)
              RoleEntry.fromMap(Map<String, dynamic>.from(role)),
        ],
        createdAt: doc['created_at'] as DateTime? ?? DateTime.now(),
        updatedAt: doc['updated_at'] as DateTime? ?? DateTime.now(),
        lastLogin: doc['last_login'] as DateTime?,
      );

  final ObjectId? id;
  final String name;
  final String phone;
  final String email;
  final String passwordHash;
  final String? avatar;
  final bool isActive;
  final List<RoleEntry> roles;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  Map<String, Object?> toDocument() => {
        'name': name,
        'phone': phone,
        'email': email,
        'password': passwordHash,
        'avatar': avatar,
        'is_active': isActive,
        'roles': [for (final role in roles) role.toMap()],
        'created_at': createdAt.toUtc(),
        'updated_at': updatedAt.toUtc(),
        'last_login': lastLogin?.toUtc(),
      };

  Map<String, Object?> toJson() => {
        'id': idHex(id),
        'name': name,
        'phone': phone,
        'email': email,
        'avatar': avatar,
        'is_active': isActive,
        'roles': [for (final role in roles) role.toMap()],
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'last_login': lastLogin?.toIso8601String(),
      };

  /// Slim shape used by dropdown endpoints (v4 selected only id+name).
  Map<String, Object?> toRefJson() => {'id': idHex(id), 'name': name};
}
