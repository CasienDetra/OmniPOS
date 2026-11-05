// Integration tests for stock tracking against a running POS api.
//
// Requires the stack up (docker compose up -d from repo root). Override the
// target with API_BASE_URL. Everything created here is prefixed `zz-test-`
// and deleted again at the end of the run.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final base = Uri.parse(
  Platform.environment['API_BASE_URL'] ?? 'http://localhost:3000',
);

String adminToken = '';
String cashierToken = '';
String? typeId;
String? productId;
final saleIds = <String>[];

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
    '/api/v1/account/auth/login',
    body: {'username': username, 'password': password},
  );
  if (res.statusCode != 200) {
    throw StateError(
      'login failed for $username: ${res.statusCode} ${res.body}',
    );
  }
  return (jsonOf(res)['data'] as Map)['token'] as String;
}

Future<String?> probeServer() async {
  try {
    final probe = await call(
      'GET',
      '/api/v1/testing/basic',
    ).timeout(const Duration(seconds: 3));
    if (probe.statusCode != 200) {
      return 'POS api answered ${probe.statusCode} at $base';
    }
    return null;
  } catch (_) {
    return 'POS api not reachable at $base — run `docker compose up -d` first';
  }
}

Future<Map<String, dynamic>> productJson() async {
  final res = await call(
    'GET',
    '/api/v1/admin/products/$productId',
    token: adminToken,
  );
  expect(res.statusCode, 200, reason: res.body);
  return jsonOf(res)['data'] as Map<String, dynamic>;
}

void main() async {
  final unreachable = await probeServer();
  if (unreachable != null) {
    test('POS api stock suite', () {}, skip: unreachable);
    return;
  }

  setUpAll(() async {
    adminToken = await login('admin@pos.local', 'admin123');
    cashierToken = await login('cashier@pos.local', 'cashier123');

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final createdType = await call(
      'POST',
      '/api/v1/admin/types',
      token: adminToken,
      body: {'name': 'zz-test-stock-$stamp'},
    );
    expect(createdType.statusCode, 201, reason: createdType.body);
    typeId = (jsonOf(createdType)['data'] as Map)['id'] as String;

    final created = await call(
      'POST',
      '/api/v1/admin/products',
      token: adminToken,
      body: {
        'name': 'zz-test-stock-product',
        'code': 'ZZ-$stamp',
        'type': typeId,
        'unit_price': 2,
        'stock': 2,
        'low_stock_threshold': 3,
      },
    );
    expect(created.statusCode, 201, reason: created.body);
    productId = (jsonOf(created)['data'] as Map)['id'] as String;
  });

  // Every test starts from the same shelf.
  setUp(() async {
    final res = await call(
      'PUT',
      '/api/v1/admin/products/$productId',
      token: adminToken,
      body: {'stock': 2},
    );
    expect(res.statusCode, 200, reason: res.body);
  });

  tearDownAll(() async {
    for (final id in saleIds) {
      await call('DELETE', '/api/v1/admin/sales/$id', token: adminToken);
    }
    if (productId != null) {
      await call(
        'DELETE',
        '/api/v1/admin/products/$productId',
        token: adminToken,
      );
    }
    if (typeId != null) {
      await call('DELETE', '/api/v1/admin/types/$typeId', token: adminToken);
    }
  });

  test('a product keeps the stock figures it was created with', () async {
    final product = await productJson();
    expect(product['stock'], 2);
    expect(product['low_stock_threshold'], 3);
  });

  test('it is reported as low while at or below the warning line', () async {
    final res = await call(
      'GET',
      '/api/v1/admin/products/low-stock',
      token: adminToken,
    );
    expect(res.statusCode, 200, reason: res.body);
    final body = jsonOf(res)['data'] as Map;
    final products = (body['products'] as List).cast<Map<String, dynamic>>();
    final row = products.firstWhere(
      (product) => product['id'] == productId,
      orElse: () => throw StateError(
        'product missing from low-stock: ${res.body}',
      ),
    );
    expect(row['stock'], 2);
    expect(body['total'], greaterThanOrEqualTo(1));
  });

  test('a cash sale decrements the shelf', () async {
    final res = await call(
      'POST',
      '/api/v1/cashier/ordering/order',
      token: cashierToken,
      body: {
        'cart': jsonEncode({productId: 1}),
      },
    );
    expect(res.statusCode, 201, reason: res.body);
    saleIds.add((jsonOf(res)['data'] as Map)['id'] as String);

    expect((await productJson())['stock'], 1);
  });

  test('a sale for more than is left is refused', () async {
    final res = await call(
      'POST',
      '/api/v1/cashier/ordering/order',
      token: cashierToken,
      body: {
        'cart': jsonEncode({productId: 3}),
      },
    );
    expect(res.statusCode, 409, reason: res.body);
    expect(jsonOf(res)['error'], contains('Only 2'));

    // Nothing was sold and nothing was taken.
    expect((await productJson())['stock'], 2);
  });

  test('an update can set and clear the tracking', () async {
    final set = await call(
      'PUT',
      '/api/v1/admin/products/$productId',
      token: adminToken,
      body: {'stock': 10},
    );
    expect(set.statusCode, 200, reason: set.body);
    expect((jsonOf(set)['data'] as Map)['stock'], 10);

    final clear = await call(
      'PUT',
      '/api/v1/admin/products/$productId',
      token: adminToken,
      body: {'stock': null},
    );
    expect(clear.statusCode, 200, reason: clear.body);
    expect((jsonOf(clear)['data'] as Map)['stock'], isNull);

    final low = await call(
      'GET',
      '/api/v1/admin/products/low-stock',
      token: adminToken,
    );
    final products = ((jsonOf(low)['data'] as Map)['products'] as List)
        .cast<Map<String, dynamic>>();
    expect(products.any((product) => product['id'] == productId), isFalse);
  });

  test('the dashboard counts what needs restocking', () async {
    final res = await call(
      'GET',
      '/api/v1/admin/dashboard',
      token: adminToken,
    );
    expect(res.statusCode, 200, reason: res.body);
    expect((jsonOf(res)['data'] as Map)['low_stock'], greaterThanOrEqualTo(1));
  });
}
