import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../config/app_config.dart';
import '../core/auth.dart';
import '../core/exceptions.dart';
import '../models/user.dart';

class TokenService {
  const TokenService();

  static const tokenTtl = Duration(hours: 24);

  /// Mirrors v4's payload: the whole user summary lives inside the token.
  String generate(User user) {
    final jwt = JWT({
      'user': {
        'id': user.id!.oid,
        'name': user.name,
        'phone': user.phone,
        'email': user.email,
        'avatar': user.avatar,
        'created_at': user.createdAt.toIso8601String(),
        'roles': [
          for (final role in user.roles)
            {'id': role.id, 'name': role.name, 'is_default': role.isDefault},
        ],
      },
    });
    return jwt.sign(
      SecretKey(AppConfig.current.jwtSecret),
      expiresIn: tokenTtl,
    );
  }

  /// Verifies signature + expiry; throws 401 otherwise.
  AuthUser verify(String token) {
    late final JWT jwt;
    try {
      jwt = JWT.verify(token, SecretKey(AppConfig.current.jwtSecret));
    } on JWTExpiredException {
      throw const UnauthorizedException('Token has expired');
    } catch (_) {
      throw const UnauthorizedException('Invalid token');
    }
    final payload = jwt.payload;
    final user = payload is Map ? payload['user'] : null;
    if (user is! Map) {
      throw const UnauthorizedException('Invalid token payload');
    }
    return AuthUser.fromJwt(user.cast<String, dynamic>());
  }
}
