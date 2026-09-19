import 'package:bcrypt/bcrypt.dart';
import 'package:mongo_dart/mongo_dart.dart';

import '../core/auth.dart';
import '../core/exceptions.dart';
import '../core/pagination.dart';
import '../models/user.dart';
import '../models/user_log.dart';
import '../repositories/mongo.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.ip,
    required this.browser,
    required this.os,
    required this.platform,
  });

  final String ip;
  final String browser;
  final String os;
  final String platform;

  /// Rough device tracking from headers (v4 used a dedicated middleware).
  static DeviceInfo fromHeaders({
    required Map<String, String> headers,
    required String defaultPlatform,
  }) {
    final ua = (headers['user-agent'] ?? '').toLowerCase();
    String browser = 'Unknown';
    for (final entry in const {
      'edg': 'Edge',
      'chrome': 'Chrome',
      'firefox': 'Firefox',
      'safari': 'Safari',
      'dart': 'Dart',
      'curl': 'cURL',
    }.entries) {
      if (ua.contains(entry.key)) {
        browser = entry.value;
        break;
      }
    }
    String os = 'Unknown';
    for (final entry in const {
      'windows': 'Windows',
      'android': 'Android',
      'iphone': 'iOS',
      'mac os': 'macOS',
      'linux': 'Linux',
    }.entries) {
      if (ua.contains(entry.key)) {
        os = entry.value;
        break;
      }
    }
    final forwarded = headers['x-forwarded-for'];
    final ip = (forwarded?.split(',').first.trim() ??
            headers['x-real-ip'] ??
            'unknown')
        .trim();
    return DeviceInfo(
      ip: ip,
      browser: browser,
      os: os,
      platform: defaultPlatform,
    );
  }
}

class AuthService {
  const AuthService();

  static String hashPassword(String plain) =>
      BCrypt.hashpw(plain, BCrypt.gensalt(logRounds: 10));

  static bool verifyPassword(String plain, String hash) {
    try {
      return BCrypt.checkpw(plain, hash);
    } catch (_) {
      return false;
    }
  }

  /// v4 semantics: username may be phone or email, inactive accounts and
  /// wrong passwords both return the generic 'Invalid credentials'.
  Future<User> login({
    required String username,
    required String password,
  }) async {
    final doc = await findDoc('users', {
      r'$or': [
        {'phone': username},
        {'email': username},
      ],
    });
    if (doc == null) {
      throw const UnauthorizedException('Invalid credentials');
    }
    final user = User.fromDocument(doc);
    if (!user.isActive || !verifyPassword(password, user.passwordHash)) {
      throw const UnauthorizedException('Invalid credentials');
    }
    return user;
  }

  Future<void> recordLogin(User user, DeviceInfo device) async {
    await insertDoc('user_logs', {
      'user_id': user.id,
      ...UserLog(
        action: 'login',
        ip: device.ip,
        browser: device.browser,
        os: device.os,
        platform: device.platform,
        timestamp: DateTime.now().toUtc(),
      ).toDocument(),
    });
    await updateById('users', user.id!.oid, {
      'last_login': DateTime.now().toUtc(),
    });
  }

  Future<User> loadUser(ObjectId id) async {
    final doc = await findDoc('users', {'_id': id});
    if (doc == null) {
      throw const UnauthorizedException('Account no longer exists');
    }
    return User.fromDocument(doc);
  }

  /// Flips the default role inside the users document (v4 used a pivot
  /// table; roles are embedded here). Returns the updated user.
  Future<User> switchRole(AuthUser auth, int roleId) async {
    final user = await loadUser(asObjectId(auth.id));
    if (!user.roles.any((role) => role.id == roleId)) {
      throw ForbiddenException('You are not assigned to this role');
    }
    final roles = [
      for (final role in user.roles)
        RoleEntry(
          id: role.id,
          name: role.name,
          isDefault: role.id == roleId,
        ),
    ];
    await updateById('users', user.id!.oid, {
      'roles': [for (final role in roles) role.toMap()],
      'updated_at': DateTime.now().toUtc(),
    });
    return User(
      id: user.id,
      name: user.name,
      phone: user.phone,
      email: user.email,
      passwordHash: user.passwordHash,
      avatar: user.avatar,
      isActive: user.isActive,
      roles: roles,
      createdAt: user.createdAt,
      updatedAt: DateTime.now().toUtc(),
      lastLogin: user.lastLogin,
    );
  }

  Future<List<Map<String, Object?>>> logsOf(String userId,
      {int limit = 20}) async {
    final docs = await findPage(
      collection: 'user_logs',
      filter: {'user_id': asObjectId(userId)},
      sort: {'timestamp': -1},
      limit: limit,
    );
    return [for (final doc in docs) UserLog.fromDocument(doc).toJson()];
  }
}
