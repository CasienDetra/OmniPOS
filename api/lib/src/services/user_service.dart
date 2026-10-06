import 'package:mongo_dart/mongo_dart.dart';

import '../core/auth.dart';
import '../core/exceptions.dart';
import '../core/pagination.dart';
import '../models/user.dart';
import '../repositories/mongo.dart';
import 'auth_service.dart';

class UserService {
  const UserService();

  Future<Map<String, Object?>> list({
    required int page,
    required int limit,
    String? key,
  }) async {
    final filter = <String, Object?>{
      if (key != null)
        r'$or': [
          {'name': RegExp(RegExp.escape(key), caseSensitive: false)},
          {'email': RegExp(RegExp.escape(key), caseSensitive: false)},
          {'phone': RegExp(RegExp.escape(key), caseSensitive: false)},
        ],
    };
    final total = await countDocs('users', filter);
    final docs = await findPage(
      collection: 'users',
      filter: filter,
      sort: {'created_at': -1},
      skip: (page - 1) * limit,
      limit: limit,
    );
    return {
      'data': [for (final doc in docs) User.fromDocument(doc).toJson()],
      'pagination': buildPagination(page: page, limit: limit, total: total),
    };
  }

  Future<User> get(String rawId) async {
    final doc = await findDoc('users', {'_id': asObjectId(rawId)});
    if (doc == null) {
      throw NotFoundException('User "$rawId" not found');
    }
    return User.fromDocument(doc);
  }

  Future<List<User>> allRefs() async {
    final docs = await findPage(
      collection: 'users',
      sort: {'name': 1},
      limit: 200,
    );
    return [for (final doc in docs) User.fromDocument(doc)];
  }

  Future<User> create({
    required String name,
    required String phone,
    required String email,
    required String password,
    required List<int> roleIds,
  }) async {
    _ensureRoleIds(roleIds);
    await _ensureUnique(email: email, phone: phone);

    final now = DateTime.now().toUtc();
    final user = User(
      name: name,
      phone: phone,
      email: email,
      passwordHash: AuthService.hashPassword(password),
      avatar: null,
      isActive: true,
      roles: [
        for (final (index, roleId) in roleIds.indexed)
          RoleEntry(
            id: roleId,
            name: Role.names[roleId] ?? 'Unknown',
            isDefault: index == 0,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    final id = await insertDoc('users', user.toDocument());
    return User(
      id: id,
      name: user.name,
      phone: user.phone,
      email: user.email,
      passwordHash: user.passwordHash,
      avatar: user.avatar,
      isActive: user.isActive,
      roles: user.roles,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
    );
  }

  Future<void> update(
    String rawId, {
    String? name,
    String? phone,
    String? email,
    List<int>? roleIds,
  }) async {
    final existing = await get(rawId);
    final fields = <String, Object?>{
      if (name != null) 'name': name,
      if (phone != null && phone != existing.phone) 'phone': phone,
      if (email != null && email != existing.email) 'email': email,
    };
    if (phone != null || email != null) {
      await _ensureUnique(
        email: email ?? existing.email,
        phone: phone ?? existing.phone,
        excludeId: existing.id,
      );
    }
    if (roleIds != null) {
      _ensureRoleIds(roleIds);
      fields['roles'] = [
        for (final (index, roleId) in roleIds.indexed)
          {
            'id': roleId,
            'name': Role.names[roleId] ?? 'Unknown',
            'is_default': index == 0,
          },
      ];
    }
    if (fields.isEmpty) return;
    fields['updated_at'] = DateTime.now().toUtc();
    await updateById('users', rawId, fields);
  }

  Future<void> setActive(String rawId, bool isActive) async {
    await get(rawId);
    await updateById('users', rawId, {
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc(),
    });
  }

  Future<void> resetPassword(String rawId, String password) async {
    await get(rawId);
    await updateById('users', rawId, {
      'password': AuthService.hashPassword(password),
      'updated_at': DateTime.now().toUtc(),
    });
  }

  Future<void> delete(String rawId) async {
    await get(rawId);
    await deleteById('users', rawId);
  }

  Future<void> updateProfile(
    ObjectId id, {
    String? name,
    String? phone,
    String? email,
    String? avatar,
  }) async {
    final fields = <String, Object?>{
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (avatar != null) 'avatar': avatar,
      'updated_at': DateTime.now().toUtc(),
    };
    if (fields.length == 1) return;
    await updateById('users', id.oid, fields);
  }

  Future<void> changePassword(
    ObjectId id,
    String oldPassword,
    String newPassword,
  ) async {
    final doc = await findDoc('users', {'_id': id});
    if (doc == null) {
      throw const UnauthorizedException('Account no longer exists');
    }
    final user = User.fromDocument(doc);
    if (!AuthService.verifyPassword(oldPassword, user.passwordHash)) {
      throw const BadRequestException('Current password is incorrect');
    }
    await updateById('users', id.oid, {
      'password': AuthService.hashPassword(newPassword),
      'updated_at': DateTime.now().toUtc(),
    });
  }

  void _ensureRoleIds(List<int> roleIds) {
    if (roleIds.isEmpty) {
      throw InvalidEntityException(['roles must not be empty']);
    }
    for (final roleId in roleIds) {
      if (!Role.names.containsKey(roleId)) {
        throw InvalidEntityException(['unknown role id "$roleId"']);
      }
    }
  }

  Future<void> _ensureUnique({
    required String email,
    required String phone,
    ObjectId? excludeId,
  }) async {
    final clash = await findDoc('users', {
      r'$or': [
        {'email': email},
        {'phone': phone},
      ],
      if (excludeId != null) '_id': {r'$ne': excludeId},
    });
    if (clash != null) {
      throw ConflictException('Email or phone already in use');
    }
  }
}
