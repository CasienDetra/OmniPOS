import 'package:dart_frog/dart_frog.dart';

import 'exceptions.dart';

/// Role ids follow v4's RoleEnum.
class Role {
  static const int admin = 1;
  static const int cashier = 2;

  static const Map<int, String> names = {admin: 'Admin', cashier: 'Cashier'};
}

class RoleEntry {
  const RoleEntry({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final int id;
  final String name;
  final bool isDefault;

  static RoleEntry fromMap(Map<String, dynamic> map) => RoleEntry(
    id: (map['id'] as num).toInt(),
    name: map['name'] as String? ?? Role.names[map['id']] ?? 'Unknown',
    isDefault: map['is_default'] == true,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'is_default': isDefault,
  };
}

/// Authenticated identity extracted from the bearer token and provided to
/// every protected route through the auth middleware.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.avatar,
    required this.roles,
  });

  factory AuthUser.fromJwt(Map<String, dynamic> user) {
    final roles = [
      for (final role in (user['roles'] as List? ?? const []))
        if (role is Map) RoleEntry.fromMap(Map<String, dynamic>.from(role)),
    ];
    return AuthUser(
      id: user['id'] as String,
      name: user['name'] as String? ?? '',
      phone: user['phone'] as String? ?? '',
      email: user['email'] as String? ?? '',
      avatar: user['avatar'] as String?,
      roles: roles,
    );
  }

  final String id;
  final String name;
  final String phone;
  final String email;
  final String? avatar;
  final List<RoleEntry> roles;

  /// Default role from the token, falling back to the first role like v4's
  /// JwtMiddleware did.
  int get defaultRoleId {
    for (final role in roles) {
      if (role.isDefault) return role.id;
    }
    return roles.isEmpty ? 0 : roles.first.id;
  }

  bool hasRole(int roleId) => roles.any((role) => role.id == roleId);
}

/// Read the authenticated user injected by the root auth middleware.
AuthUser authUser(RequestContext context) {
  try {
    return context.read<AuthUser>();
  } catch (_) {
    throw const UnauthorizedException('Authentication required');
  }
}

/// Route-level role check on top of the middleware's path guard (v4 used
/// middleware + guard; both are kept as defense in depth).
void requireRole(RequestContext context, int roleId) {
  final user = authUser(context);
  if (!user.hasRole(roleId)) {
    throw ForbiddenException('Requires ${Role.names[roleId]} role');
  }
}
