// E2E smoke test against a running POS stack.
//
// Usage: dart run scripts/smoke.dart [base-url]   (default http://localhost:3000)
// Flow: health -> logins -> authz probes -> catalogue read -> place order ->
//       my sales -> sale detail -> invoice PDF -> admin delete (cleanup).
// Prints one PASS/FAIL line per step, exits 1 if any step fails.
import 'dart:convert';
import 'dart:io';

int failures = 0;
final client = HttpClient();

Future<void> main(List<String> argv) async {
  final target = Uri.parse(
    argv.isNotEmpty ? argv.first : 'http://localhost:3000',
  );

  await step(
    target,
    'GET',
    '/api/testing/basic',
    label: 'health: public testing endpoint',
    expectStatus: 200,
    check: (json) => json?['success'] == true,
  );

  final admin = await step(
    target,
    'POST',
    '/api/account/auth/login',
    label: 'login admin',
    body: const {'username': 'admin@pos.local', 'password': 'admin123'},
    expectStatus: 200,
  );
  if (admin == null) bail();
  final adminToken = (admin['data']! as Map)['token']! as String;

  final cashier = await step(
    target,
    'POST',
    '/api/account/auth/login',
    label: 'login cashier',
    body: const {'username': 'cashier@pos.local', 'password': 'cashier123'},
    expectStatus: 200,
  );
  if (cashier == null) bail();
  final cashierToken = (cashier['data']! as Map)['token']! as String;

  await step(
    target,
    'GET',
    '/api/admin/products',
    label: 'authz: cashier on admin route is 403',
    token: cashierToken,
    expectStatus: 403,
  );
  await step(
    target,
    'GET',
    '/api/admin/products',
    label: 'authz: no token is 401',
    expectStatus: 401,
  );

  final listing = await step(
    target,
    'GET',
    '/api/cashier/ordering/products',
    label: 'cashier ordering products',
    token: cashierToken,
    expectStatus: 200,
    check: (json) => (json!['data']! as List).cast<Map<String, dynamic>>().any(
      (t) => (t['products']! as List).isNotEmpty,
    ),
  );
  if (listing == null) bail();
  final type = (listing['data']! as List)
      .cast<Map<String, dynamic>>()
      .firstWhere((t) => (t['products']! as List).isNotEmpty);
  final product = (type['products']! as List)
      .cast<Map<String, dynamic>>()
      .first;

  final order = await step(
    target,
    'POST',
    '/api/cashier/ordering/order',
    label: 'place order (2 x ${product['name']})',
    token: cashierToken,
    body: {
      'cart': jsonEncode({product['id']: 2}),
      'platform': 'Web',
    },
    expectStatus: 201,
    check: (json) {
      final data = json!['data']! as Map<String, dynamic>;
      final expected = (product['unit_price']! as num) * 2;
      return RegExp(r'^\d{7}$').hasMatch(data['receipt_number']! as String) &&
          (data['total_price']! as num) == expected;
    },
  );
  if (order == null) bail();
  final orderId = (order['data']! as Map)['id']! as String;

  await step(
    target,
    'GET',
    '/api/cashier/sales?page=1&limit=50',
    label: 'my sales includes new order',
    token: cashierToken,
    expectStatus: 200,
    check: (json) =>
        (json!['data']! as List).any((o) => (o as Map)['id'] == orderId),
  );

  await step(
    target,
    'GET',
    '/api/cashier/sales/$orderId',
    label: 'sale detail',
    token: cashierToken,
    expectStatus: 200,
  );

  await step(
    target,
    'GET',
    '/api/reports/invoice/$orderId',
    label: 'invoice PDF (own order)',
    token: cashierToken,
    expectStatus: 200,
    binary: true,
  );

  await step(
    target,
    'GET',
    '/api/reports/invoice/000000000000000000000000',
    label: 'invoice 404 for unknown id',
    token: adminToken,
    expectStatus: 404,
  );

  await step(
    target,
    'DELETE',
    '/api/admin/sales/$orderId',
    label: 'cleanup: admin deletes test order',
    token: adminToken,
    expectStatus: 200,
  );

  bail();
}

/// Runs one request, prints PASS/FAIL, returns decoded JSON (null on failure
/// or binary response).
Future<Map<String, dynamic>?> step(
  Uri target,
  String method,
  String path, {
  required String label,
  String? token,
  Object? body,
  required int expectStatus,
  bool binary = false,
  bool Function(Map<String, dynamic>? json)? check,
}) async {
  final uri = target.replace(
    path: Uri.parse(path).path,
    query: Uri.parse(path).hasQuery ? Uri.parse(path).query : null,
  );
  final request = await client
      .openUrl(method, uri)
      .timeout(const Duration(seconds: 10));
  if (token != null) request.headers.set('authorization', 'Bearer $token');
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
  }
  final response = await request.close().timeout(const Duration(seconds: 15));
  final bytes = await response.fold<List<int>>(<int>[], (a, b) => a..addAll(b));

  var ok = response.statusCode == expectStatus;
  Map<String, dynamic>? json;
  if (ok && binary) {
    ok =
        String.fromCharCodes(
              bytes.sublist(0, bytes.length < 5 ? bytes.length : 5),
            ) ==
            '%PDF-' &&
        response.headers.contentType?.mimeType == 'application/pdf';
  } else if (ok) {
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on FormatException {
      ok = false;
    }
  }
  if (ok && check != null) ok = check(json) == true;

  print(
    '${ok ? 'PASS' : 'FAIL'}  $label '
    '(${response.statusCode}${ok ? '' : ', expected $expectStatus'})',
  );
  if (!ok) {
    failures++;
    return null;
  }
  return json;
}

Never bail() {
  client.close(force: true);
  if (failures > 0) {
    print('SMOKE FAILED: $failures step(s)');
    exit(1);
  }
  print('SMOKE OK');
  exit(0);
}
