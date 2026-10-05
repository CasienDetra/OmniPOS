// Integration tests against a running POS api instance.
//
// Requires the stack up (docker compose up -d from repo root). Override the
// target with API_BASE_URL. Tests create data prefixed `zz-test-` and delete
// it again at the end of the run.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final base = Uri.parse(
  Platform.environment['API_BASE_URL'] ?? 'http://localhost:3000',
);

String adminToken = '';
String cashierToken = '';
String? tempCashierId;
String? tempCashierToken;
final placedOrderIds = <String>[];

Future<http.Response> call(
  String method,
  String path, {
  String? token,
  Object? body,
}) async {
  final request = http.Request(method, base.replace(path: path));
  if (token != null) request.headers['authorization'] = 'Bearer $token';
  if (body != null) {
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  return http.Response.fromStream(await request.send());
}

Map<String, dynamic> jsonOf(http.Response res) =>
    jsonDecode(res.body) as Map<String, dynamic>;

Future<String> login(String username, String password) async {
  final res = await call(
    'POST',
    '/api/account/auth/login',
    body: {'username': username, 'password': password},
  );
  if (res.statusCode != 200) {
    throw StateError(
      'login failed for $username: ${res.statusCode} ${res.body}',
    );
  }
  return (jsonOf(res)['data'] as Map)['token'] as String;
}

void main() {
  var serverReady = false;

  setUpAll(() async {
    try {
      final probe = await call(
        'GET',
        '/api/testing/basic',
      ).timeout(const Duration(seconds: 3));
      if (probe.statusCode != 200) throw const SocketException('not ready');
      serverReady = true;
    } catch (_) {
      markTestSkipped(
        'POS api not reachable at $base — run `docker compose up -d` first',
      );
      return;
    }
    adminToken = await login('admin@pos.local', 'admin123');
    cashierToken = await login('cashier@pos.local', 'cashier123');
  });

  setUp(() {
    if (!serverReady) markTestSkipped('server not reachable');
  });

  tearDownAll(() async {
    if (!serverReady || adminToken.isEmpty) return;
    for (final id in placedOrderIds) {
      await call('DELETE', '/api/admin/sales/$id', token: adminToken);
    }
    if (tempCashierId != null) {
      await call(
        'DELETE',
        '/api/admin/users/$tempCashierId',
        token: adminToken,
      );
    }
  });

  group('auth guard', () {
    test('public testing endpoint needs no token', () async {
      final res = await call('GET', '/api/testing/basic');
      expect(res.statusCode, 200);
      expect(jsonOf(res)['success'], isTrue);
    });

    test('protected endpoint without token is 401', () async {
      final res = await call('GET', '/api/admin/products');
      expect(res.statusCode, 401);
    });

    test('malformed Authorization header is 401', () async {
      final request = http.Request(
        'GET',
        base.replace(path: '/api/admin/products'),
      )..headers['authorization'] = 'Token abc';
      final res = await http.Response.fromStream(await request.send());
      expect(res.statusCode, 401);
    });

    test('garbage token is 401', () async {
      final res = await call(
        'GET',
        '/api/admin/products',
        token: 'abc.def.ghi',
      );
      expect(res.statusCode, 401);
    });

    test('wrong password is 401 with generic message', () async {
      final res = await call(
        'POST',
        '/api/account/auth/login',
        body: {'username': 'admin@pos.local', 'password': 'nope'},
      );
      expect(res.statusCode, 401);
      expect(jsonOf(res)['error'], 'Invalid credentials');
    });

    test('cashier is 403 on admin paths', () async {
      final res = await call('GET', '/api/admin/products', token: cashierToken);
      expect(res.statusCode, 403);
    });

    test('admin is 403 on cashier paths', () async {
      final res = await call(
        'GET',
        '/api/cashier/ordering/products',
        token: adminToken,
      );
      expect(res.statusCode, 403);
    });
  });

  group('catalogue reads', () {
    test('admin lists products with pagination envelope', () async {
      final res = await call('GET', '/api/admin/products', token: adminToken);
      expect(res.statusCode, 200);
      final body = jsonOf(res);
      expect(body['data'], isA<List<dynamic>>());
      expect(body['pagination'], isA<Map<String, dynamic>>());
      expect(body['data'], isNotEmpty, reason: 'seeded catalogue expected');
    });

    test('cashier sees types with nested active products', () async {
      final res = await call(
        'GET',
        '/api/cashier/ordering/products',
        token: cashierToken,
      );
      expect(res.statusCode, 200);
      final types = (jsonOf(res)['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(types, isNotEmpty);
      final withProducts = types.firstWhere(
        (t) => (t['products'] as List).isNotEmpty,
      );
      expect(withProducts['products'], isNotEmpty);
    });
  });

  group('checkout validation', () {
    test('missing cart is 422', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'platform': 'Web'},
      );
      expect(res.statusCode, 422);
    });

    test('empty cart is 422', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{}', 'platform': 'Web'},
      );
      expect(res.statusCode, 422);
    });

    test('non-positive qty is 422', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{"000000000000000000000001": 0}', 'platform': 'Web'},
      );
      expect(res.statusCode, 422);
    });

    test('malformed cart string is 422', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': 'not json', 'platform': 'Web'},
      );
      expect(res.statusCode, 422);
    });

    test('unknown product is 404', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{"0000000000000000000000ff": 1}', 'platform': 'Web'},
      );
      expect(res.statusCode, 404);
    });

    test('malformed product id is 404', () async {
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{"nope": 1}', 'platform': 'Web'},
      );
      expect(res.statusCode, 404);
    });
  });

  group('order lifecycle', () {
    late String firstOrderId;
    late String firstReceipt;

    test('cashier places an order', () async {
      final listing = await call(
        'GET',
        '/api/cashier/ordering/products',
        token: cashierToken,
      );
      final types = (jsonOf(listing)['data'] as List)
          .cast<Map<String, dynamic>>();
      final product =
          (types.firstWhere(
                    (t) => (t['products'] as List).isNotEmpty,
                  )['products']
                  as List)
              .cast<Map<String, dynamic>>()
              .first;
      final price = (product['unit_price'] as num).toDouble();

      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{"${product['id']}": 2}', 'platform': 'Web'},
      );
      expect(res.statusCode, 201);
      final order = jsonOf(res)['data'] as Map;
      firstOrderId = order['id'] as String;
      firstReceipt = order['receipt_number'] as String;
      placedOrderIds.add(firstOrderId);
      expect(firstReceipt, matches(RegExp(r'^\d{7}$')));
      expect(order['total_price'], price * 2);
      expect(order['items'], hasLength(1));
      expect(
        (order['items'] as List).first,
        containsPair('line_price', price * 2),
      );
    });

    test('receipt numbers increment sequentially', () async {
      final listing = await call(
        'GET',
        '/api/cashier/ordering/products',
        token: cashierToken,
      );
      final types = (jsonOf(listing)['data'] as List)
          .cast<Map<String, dynamic>>();
      final product =
          (types.firstWhere(
                    (t) => (t['products'] as List).isNotEmpty,
                  )['products']
                  as List)
              .cast<Map<String, dynamic>>()
              .first;
      final res = await call(
        'POST',
        '/api/cashier/ordering/order',
        token: cashierToken,
        body: {'cart': '{"${product['id']}": 1}', 'platform': 'Web'},
      );
      expect(res.statusCode, 201);
      final order = jsonOf(res)['data'] as Map;
      placedOrderIds.add(order['id'] as String);
      final second = int.parse(order['receipt_number'] as String);
      final expected = (int.parse(firstReceipt) + 1) % 10000000;
      expect(second, expected);
    });

    test('cashier reads own order detail', () async {
      final res = await call(
        'GET',
        '/api/cashier/sales/$firstOrderId',
        token: cashierToken,
      );
      expect(res.statusCode, 200);
      expect((jsonOf(res)['data'] as Map)['id'], firstOrderId);
    });

    test('invoice PDF renders for the owning cashier', () async {
      final res = await call(
        'GET',
        '/api/reports/invoice/$firstOrderId',
        token: cashierToken,
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('application/pdf'));
      expect(String.fromCharCodes(res.bodyBytes.take(5)), '%PDF-');
    });

    test('invoice without token is 401', () async {
      final res = await call('GET', '/api/reports/invoice/$firstOrderId');
      expect(res.statusCode, 401);
    });

    test('another cashier gets 403 on the order and its invoice', () async {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final created = await call(
        'POST',
        '/api/admin/users',
        token: adminToken,
        body: {
          'name': 'zz-test cashier',
          'phone': '09$stamp',
          'email': 'zz-test-$stamp@pos.local',
          'password': 'test1234',
          'roles': [2],
        },
      );
      expect(created.statusCode, 201);
      tempCashierId = (jsonOf(created)['data'] as Map)['id'] as String;
      tempCashierToken = await login('zz-test-$stamp@pos.local', 'test1234');

      final detail = await call(
        'GET',
        '/api/cashier/sales/$firstOrderId',
        token: tempCashierToken,
      );
      expect(detail.statusCode, 403);

      final invoice = await call(
        'GET',
        '/api/reports/invoice/$firstOrderId',
        token: tempCashierToken,
      );
      expect(invoice.statusCode, 403);
    });

    test('invoice for a well-formed unknown id is 404', () async {
      final res = await call(
        'GET',
        '/api/reports/invoice/000000000000000000000000',
        token: adminToken,
      );
      expect(res.statusCode, 404);
    });

    test('cashier cannot delete another cashier order', () async {
      final res = await call(
        'DELETE',
        '/api/cashier/sales/$firstOrderId',
        token: tempCashierToken,
      );
      expect(res.statusCode, 403);
    });

    test('admin deletes the test orders', () async {
      for (final id in placedOrderIds.toList()) {
        final res = await call(
          'DELETE',
          '/api/admin/sales/$id',
          token: adminToken,
        );
        expect(res.statusCode, 200, reason: 'delete $id failed: ${res.body}');
        placedOrderIds.remove(id);
      }
      final gone = await call(
        'GET',
        '/api/admin/sales/$firstOrderId',
        token: adminToken,
      );
      expect(gone.statusCode, 404);
    });
  });
}
