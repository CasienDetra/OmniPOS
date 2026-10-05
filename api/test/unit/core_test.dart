import 'package:mongo_dart/mongo_dart.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

void main() {
  group('asObjectId', () {
    test('parses a valid 24-char hex id', () {
      final id = asObjectId('6ab11f855dc3537029037fad');
      expect(id.oid, '6ab11f855dc3537029037fad');
    });

    test('throws NotFoundException for malformed ids', () {
      for (final bad in ['', 'abc', 'not-an-id', '6ab11f855dc3537029037fa']) {
        expect(
          () => asObjectId(bad),
          throwsA(
            isA<NotFoundException>().having(
              (e) => e.statusCode,
              'statusCode',
              404,
            ),
          ),
          reason: 'should reject "$bad"',
        );
      }
    });
  });

  group('buildPagination', () {
    test('computes totalPage with ceiling', () {
      expect(buildPagination(page: 1, limit: 10, total: 25), {
        'page': 1,
        'limit': 10,
        'totalPage': 3,
        'total': 25,
      });
    });

    test('zero total yields zero pages', () {
      expect(buildPagination(page: 1, limit: 10, total: 0)['totalPage'], 0);
    });
  });

  group('parseDateParam', () {
    test('null and blank yield null', () {
      expect(parseDateParam(null), isNull);
      expect(parseDateParam('  '), isNull);
    });

    test('parses ISO dates', () {
      expect(parseDateParam('2026-10-05T00:00:00Z')?.year, 2026);
    });

    test('garbage yields null', () {
      expect(parseDateParam('yesterday'), isNull);
    });
  });

  group('queryInt', () {
    test('falls back when missing or unparseable', () {
      expect(queryInt({}, 'page', 1), 1);
      expect(queryInt({'page': 'x'}, 'page', 1), 1);
    });

    test('clamps to bounds', () {
      expect(queryInt({'page': '0'}, 'page', 1), 1);
      expect(queryInt({'page': '9999'}, 'page', 1, max: 200), 200);
    });
  });

  group('queryBool', () {
    test('accepts true/1 only', () {
      expect(queryBool({'x': 'TRUE'}, 'x'), isTrue);
      expect(queryBool({'x': '1'}, 'x'), isTrue);
      expect(queryBool({'x': 'yes'}, 'x'), isFalse);
      expect(queryBool({}, 'x', fallback: true), isTrue);
    });
  });

  group('emptyToNull', () {
    test('trims and nulls blanks', () {
      expect(emptyToNull('  '), isNull);
      expect(emptyToNull(null), isNull);
      expect(emptyToNull(' food '), 'food');
    });
  });

  group('Validator', () {
    test('requireString trims and rejects blanks', () {
      final v = Validator();
      expect(v.requireString({'name': ' Bob '}, 'name'), 'Bob');
      expect(v.requireString({'name': '  '}, 'name'), '');
      expect(v.errors, contains('name is required'));
    });

    test('requireNumber honours positive flag', () {
      final v = Validator();
      expect(v.requireNumber({'price': '1500'}, 'price', positive: true), 1500);
      expect(v.requireNumber({'price': 0}, 'price', positive: true), 0);
      expect(v.errors, contains('price must be a positive number'));
      v.errors.clear();
      expect(v.requireNumber({'price': 'abc'}, 'price'), 0);
      expect(v.errors, contains('price must be a number'));
    });

    test('throwIfInvalid raises 422 with field details', () {
      final v = Validator();
      v.requireString({}, 'name');
      expect(
        v.throwIfInvalid,
        throwsA(
          isA<InvalidEntityException>()
              .having((e) => e.statusCode, 'statusCode', 422)
              .having((e) => e.details?.length, 'details', 1),
        ),
      );
    });
  });

  group('validateBase64Image', () {
    test('accepts png data URLs', () {
      final v = Validator();
      validateBase64Image(v, 'data:image/png;base64,iVBORw0KGgo=');
      expect(v.errors, isEmpty);
    });

    test('rejects non-image mime types and bare base64', () {
      final v = Validator();
      validateBase64Image(v, 'data:application/pdf;base64,AAAA');
      validateBase64Image(v, 'iVBORw0KGgo=');
      expect(v.errors.length, 2);
    });
  });

  group('AuthUser', () {
    final jwtUser = {
      'id': ObjectId().oid,
      'name': 'Cashier One',
      'phone': '080000000002',
      'email': 'cashier@pos.local',
      'avatar': null,
      'roles': [
        {'id': Role.admin, 'name': 'Admin', 'is_default': false},
        {'id': Role.cashier, 'name': 'Cashier', 'is_default': true},
      ],
    };

    test('reads default role and membership', () {
      final user = AuthUser.fromJwt(jwtUser.cast<String, dynamic>());
      expect(user.defaultRoleId, Role.cashier);
      expect(user.hasRole(Role.admin), isTrue);
      expect(user.hasRole(Role.cashier), isTrue);
      expect(user.hasRole(99), isFalse);
    });

    test('falls back to first role when none flagged default', () {
      final map = Map<String, dynamic>.from(jwtUser);
      map['roles'] = [
        {'id': Role.admin, 'name': 'Admin', 'is_default': false},
      ];
      expect(AuthUser.fromJwt(map).defaultRoleId, Role.admin);
    });

    test('empty roles give id 0', () {
      final map = Map<String, dynamic>.from(jwtUser)
        ..['roles'] = <Map<String, dynamic>>[];
      expect(AuthUser.fromJwt(map).defaultRoleId, 0);
    });
  });
}
