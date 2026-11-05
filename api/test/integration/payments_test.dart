// Integration tests for the QR payment routes against a running POS api.
//
// Requires the stack up (docker compose up -d from repo root). Override the
// target with API_BASE_URL.
//
// These tests need no gateway credentials: the point is that the counter's two
// payment routes are guarded like every other cashier route, and that the
// callback a gateway posts to is reachable without a token and refuses to
// invent a sale. Which gateway sits behind them is configuration, so a few of
// these answers depend on it and say so. What happens once a real QR is paid is
// covered by the provider tests and by a sandbox round-trip.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final base = Uri.parse(
  Platform.environment['API_BASE_URL'] ?? 'http://localhost:3000',
);

String cashierToken = '';
String adminToken = '';

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

/// Posts [body] exactly as written, with [headers]. A signed delivery has to be
/// sent byte for byte or the signature it carries no longer describes it, which
/// is precisely the check the callback makes.
Future<http.Response> postRaw(
  String path, {
  required String body,
  Map<String, String> headers = const {},
}) async {
  final request = http.Request('POST', base.replace(path: path))
    ..headers['content-type'] = 'application/json'
    ..headers.addAll(headers)
    ..body = body;
  return http.Response.fromStream(await request.send());
}

Future<String> login(String username, String password) async {
  final res = await call(
    'POST',
    '/api/v1/account/auth/login',
    body: {'username': username, 'password': password},
  );
  if (res.statusCode != 200) {
    throw StateError('login failed for $username: ${res.body}');
  }
  return (jsonOf(res)['data'] as Map)['token'] as String;
}

/// Reason to skip the whole suite, or null when a server answers.
Future<String?> probeServer() async {
  try {
    final probe = await call('GET', '/healthz').timeout(
      const Duration(seconds: 3),
    );
    if (probe.statusCode != 200) {
      return 'POS api answered ${probe.statusCode} at $base';
    }
    return null;
  } catch (_) {
    return 'POS api not reachable at $base — run `docker compose up -d` first';
  }
}

Future<void> main() async {
  final unreachable = await probeServer();
  if (unreachable != null) {
    test('POS api payment suite', () {}, skip: unreachable);
    return;
  }

  setUpAll(() async {
    cashierToken = await login('cashier@pos.local', 'cashier123');
    adminToken = await login('admin@pos.local', 'admin123');
  });

  group('cashier payment routes need a cashier', () {
    test('opening a QR without a token is refused', () async {
      final res = await call(
        'POST',
        '/api/v1/cashier/payments',
        body: {'cart': '{}'},
      );
      expect(res.statusCode, 401);
    });

    test('an Admin token does not open a QR', () async {
      final res = await call(
        'POST',
        '/api/v1/cashier/payments',
        token: adminToken,
        body: {'cart': '{}'},
      );
      expect(res.statusCode, 403, reason: res.body);
      expect(jsonOf(res)['error'], contains('Cashier'));
    });

    test('polling a payment that was never issued is a 404', () async {
      final res = await call(
        'GET',
        '/api/v1/cashier/payments/zzdoesnotexist',
        token: cashierToken,
      );
      expect(res.statusCode, 404, reason: res.body);
    });

    test('polling a payment without a token is refused', () async {
      final res = await call(
        'GET',
        '/api/v1/cashier/payments/zzdoesnotexist',
      );
      expect(res.statusCode, 401);
    });
  });

  group('payments without credentials', () {
    test('opening a QR reports what is missing, if anything is', () async {
      final res = await call(
        'POST',
        '/api/v1/cashier/payments',
        token: cashierToken,
        body: {
          'cart': '{"000000000000000000000000": 1}',
        },
      );
      if (res.statusCode != 503) {
        // Gateway credentials are in the environment, so this run cannot
        // observe the unconfigured answer. The product id is invented, and the
        // cart is priced before the gateway is asked, so a 4xx is still owed.
        expect(res.statusCode, lessThan(500), reason: res.body);
        return;
      }
      // Whichever gateway the deployment selected, the answer has to name the
      // variable that is missing rather than fail opaquely.
      expect(
        jsonOf(res)['error'],
        matches(
          RegExp(
            'CUTLUY_API_KEY|CUTLUY_KHR_USD_RATE|PAYWAY_MERCHANT_ID'
            '|PAYMENT_PROVIDER',
          ),
        ),
        reason: res.body,
      );
    });
  });

  group('the QR image is only for the till that asked for it', () {
    const qrPath = '/api/v1/cashier/payments/zzdoesnotexist/qr';

    test('it is not drawn without a token', () async {
      final res = await call('GET', qrPath);
      expect(res.statusCode, 401);
    });

    test('an unknown transaction is a 404, not a blank code', () async {
      final res = await call('GET', qrPath, token: cashierToken);
      expect(res.statusCode, 404, reason: res.body);
    });

    test('an Admin token does not get to see a cashier code', () async {
      final res = await call('GET', qrPath, token: adminToken);
      expect(res.statusCode, 403, reason: res.body);
    });

    test('it only accepts GET', () async {
      final res = await call('POST', qrPath, token: cashierToken);
      expect(res.statusCode, 405, reason: res.body);
    });
  });

  /// One product the counter could actually sell, so a cart has a price.
  Future<String?> firstProductId() async {
    final res = await call(
      'GET',
      '/api/v1/cashier/ordering/products',
      token: cashierToken,
    );
    if (res.statusCode != 200) return null;
    for (final type in jsonOf(res)['data'] as List) {
      for (final product in (type as Map)['products'] as List) {
        final id = (product as Map)['id'];
        if (id is String && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  group('a live code is drawn here, not hosted', () {
    test('the image is SVG and is never cached', () async {
      final productId = await firstProductId();
      if (productId == null) return; // nothing seeded to sell
      final opened = await call(
        'POST',
        '/api/v1/cashier/payments',
        token: cashierToken,
        body: {
          'cart': jsonEncode({productId: 1}),
        },
      );
      if (opened.statusCode != 201) {
        // No gateway credentials in this deployment, so no code was ever
        // issued and there is nothing to draw. The 503 answer is asserted
        // above; anything else is a bug.
        expect(opened.statusCode, 503, reason: opened.body);
        return;
      }
      final tranId = (jsonOf(opened)['data'] as Map)['tran_id'] as String;
      final res = await call(
        'GET',
        '/api/v1/cashier/payments/$tranId/qr',
        token: cashierToken,
      );
      expect(res.statusCode, 200, reason: res.body);
      expect(res.headers['content-type'], startsWith('image/svg+xml'));
      // A screen refresh must not serve a code a customer has already paid.
      expect(res.headers['cache-control'], 'no-store');
      expect(res.body, startsWith('<svg '));
      expect(res.body, isNot(contains('qr_string')));
      // The code belongs to the till that opened it, and to no other.
      final stranger = await call(
        'GET',
        '/api/v1/cashier/payments/$tranId/qr',
        token: adminToken,
      );
      expect(stranger.statusCode, 403, reason: stranger.body);
    });
  });

  group('the gateway callback is public but proves nothing', () {
    // What may be asserted about a delivery from outside is what no delivery
    // can do: become money. Whether it is refused at all, and how, is the
    // selected gateway's business — CutLuy signs, PayWay does not.
    test('an unsigned delivery is never taken as payment', () async {
      final res = await call(
        'POST',
        '/api/v1/payments/callback',
        body: {'tran_id': 'zz-not-a-payment', 'status': '0'},
      );
      expect(
        res.statusCode,
        anyOf(400, 401, 503, 200, 202),
        reason: res.body,
      );
      if (res.statusCode == 200 || res.statusCode == 202) {
        // A gateway whose notifications carry no signature is only ever a
        // pointer, so the acknowledgement names a transaction and nothing more:
        // no receipt, no sale, no amount.
        final data = jsonOf(res)['data'];
        expect(
          data is Map && data.containsKey('receipt_number'),
          isFalse,
          reason: res.body,
        );
      }
    });

    test(
      'a delivery that names nothing is refused or unconfigurable',
      () async {
        final res = await call('POST', '/api/v1/payments/callback', body: {});
        expect(res.statusCode, isNot(500), reason: res.body);
        expect(
          res.statusCode,
          anyOf(400, 401, 503),
          reason: '${res.statusCode} ${res.body}',
        );
      },
    );

    test('a signature that is not hex is refused', () async {
      final res = await postRaw(
        '/api/v1/payments/callback',
        body: '{"data":{"payment":{"reference_id":"zz-not-a-payment"}}}',
        headers: {
          'x-cutluy-signature': 't=1730000000,v1=not-hex',
          'x-cutluy-event': 'payment.completed',
        },
      );
      // Rejected as a bad signature, or the deployment accepts no deliveries at
      // all. Never read as a payment.
      expect(
        res.statusCode,
        anyOf(400, 401, 503),
        reason: '${res.statusCode} ${res.body}',
      );
    });

    test('it answers without a token', () async {
      final res = await call('POST', '/api/v1/payments/callback', body: {});
      expect(res.statusCode, isNot(401));
      expect(res.statusCode, isNot(403));
    });

    test('it only accepts POST', () async {
      final res = await call('GET', '/api/v1/payments/callback');
      expect(res.statusCode, 405);
    });

    test('a token on the callback is still verified', () async {
      final res = await call(
        'POST',
        '/api/v1/payments/callback',
        token: 'not-a-real-token',
        body: {},
      );
      expect(res.statusCode, 401);
    });
  });
}
