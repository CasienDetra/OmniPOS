import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:mongo_dart/mongo_dart.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

User _fixtureUser() {
  final now = DateTime.utc(2026, 1, 1);
  return User(
    id: ObjectId(),
    name: 'Admin',
    phone: '080000000001',
    email: 'admin@pos.local',
    passwordHash: 'x',
    avatar: null,
    isActive: true,
    roles: const [RoleEntry(id: Role.admin, name: 'Admin', isDefault: true)],
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const tokens = TokenService();

  test('generate/verify round-trip preserves identity and roles', () {
    final user = _fixtureUser();
    final auth = tokens.verify(tokens.generate(user));
    expect(auth.id, user.id!.oid);
    expect(auth.name, 'Admin');
    expect(auth.email, 'admin@pos.local');
    expect(auth.defaultRoleId, Role.admin);
  });

  test('rejects garbage tokens', () {
    expect(
      () => tokens.verify('not.a.jwt'),
      throwsA(
        isA<UnauthorizedException>().having((e) => e.statusCode, 'code', 401),
      ),
    );
  });

  test('rejects tokens signed with a different secret', () {
    final user = _fixtureUser();
    final token = tokens.generate(user);
    // Corrupt the signature segment.
    final parts = token.split('.');
    final tampered = '${parts[0]}.${parts[1]}.${"A" * parts[2].length}';
    expect(
      () => tokens.verify(tampered),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('rejects a valid JWT without the user payload', () {
    expect(
      () => tokens.verify(
        JWT({'sub': 'x'}).sign(
          SecretKey(AppConfig.current.jwtSecret),
          expiresIn: const Duration(minutes: 5),
        ),
      ),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}
