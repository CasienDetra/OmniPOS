import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// A payment as CutLuy answers it: the amount is a decimal *string* on the
/// wire even though the request sends a number.
const String _createdJson =
    '{"id":"PUETcMUOKStjZsCb6zAl8kg9fMRGM85x","status":"pending",'
    '"amount":"3.66","currency":"USD",'
    '"reference_id":"2603121000001","metadata":{"pos_total":"15000"},'
    '"checkout_url":"https://pay.example.kh/p/PUETcMUOKSt",'
    '"qr_string":"00020101021226580017com.example.qr",'
    '"created_at":"2026-11-01T09:00:00.000Z",'
    '"expires_at":"2026-11-01T09:05:00.000Z"}';

const String _paymentId = 'PUETcMUOKStjZsCb6zAl8kg9fMRGM85x';

/// A client built on a transport that answers with a fixed body, and the
/// requests it was given, so a test can say what went out as well as came back.
class _Transport {
  _Transport(
    Object body, {
    int statusCode = 201,
    Map<String, String> headers = const {},
  }) {
    client = CutluyClient(
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json', ...headers},
        );
      }),
      baseUrl: 'https://cutluy.com',
      apiKey: 'ck_live_test',
    );
  }

  late final CutluyClient client;
  final List<http.Request> sent = [];

  http.Request get request => sent.single;
  Map<String, dynamic> get json =>
      jsonDecode(request.body) as Map<String, dynamic>;
}

/// A client whose calls fail the way a network fails, not the way a gateway
/// refuses.
CutluyClient _failing(Exception error) => CutluyClient(
  client: MockClient((request) async => throw error),
  baseUrl: 'https://cutluy.com',
  apiKey: 'ck_live_test',
);

/// Runs [action] and returns the rejection it raised.
Future<CutluyRejectException> _reject(Future<Object?> action) async {
  try {
    await action;
  } on CutluyRejectException catch (failure) {
    return failure;
  }
  fail('expected CutLuy to reject the call');
}

void main() {
  group('createPayment', () {
    test('sends the key as a bearer token', () async {
      final transport = _Transport(_createdJson);
      await transport.client.createPayment(amount: 3.66, referenceId: 'T1');
      expect(transport.request.method, 'POST');
      expect(
        transport.request.url.toString(),
        'https://cutluy.com/v1/payments',
      );
      expect(
        transport.request.headers['authorization'],
        'Bearer ck_live_test',
      );
      expect(
        transport.request.headers['content-type'],
        'application/json',
      );
    });

    test(
      'sends the reference id as both reference and idempotency key',
      () async {
        final transport = _Transport(_createdJson);
        await transport.client.createPayment(amount: 3.66, referenceId: 'T1');
        expect(transport.json['reference_id'], 'T1');
        expect(transport.json['idempotency_key'], 'T1');
      },
    );

    test('never sends more than two decimals', () async {
      // A cart priced in USD is a sum of divisions, so the total arrives with
      // binary noise; CutLuy answers that with `invalid_amount`.
      final cases = <(double, double)>[
        (0.1 + 0.2, 0.3),
        (3.666, 3.67),
        (15.0, 15.0),
        (0.004, 0.0),
      ];
      for (final (amount, expected) in cases) {
        final transport = _Transport(_createdJson);
        await transport.client.createPayment(
          amount: amount,
          referenceId: 'T${expected.toString().replaceAll('.', '')}',
        );
        final sent = transport.json['amount'];
        expect(sent, expected, reason: '$amount');
        expect(
          sent.toString().split('.').last.length,
          lessThanOrEqualTo(2),
          reason: '$amount sent as $sent',
        );
      }
    });

    test('omits metadata it was not given', () async {
      final absent = _Transport(_createdJson);
      await absent.client.createPayment(amount: 1, referenceId: 'T1');
      expect(absent.json.containsKey('metadata'), isFalse);

      final blank = _Transport(_createdJson);
      await blank.client.createPayment(
        amount: 1,
        referenceId: 'T1',
        metadata: const {},
      );
      expect(blank.json.containsKey('metadata'), isFalse);

      final full = _Transport(_createdJson);
      await full.client.createPayment(
        amount: 1,
        referenceId: 'T1',
        metadata: const {'pos_currency': 'KHR'},
      );
      expect(full.json['metadata'], {'pos_currency': 'KHR'});
    });

    test('reads back the created payment', () async {
      final transport = _Transport(_createdJson);
      final payment = await transport.client.createPayment(
        amount: 3.66,
        referenceId: '2603121000001',
      );
      expect(payment.id, _paymentId);
      expect(payment.status, CutluyPaymentStatus.pending);
      expect(payment.amount, 3.66);
      expect(payment.currency, 'USD');
      expect(payment.referenceId, '2603121000001');
      expect(
        payment.checkoutUrl,
        startsWith('https://pay.example.kh/p/'),
      );
      expect(payment.qrString, startsWith('000201010212'));
      expect(
        payment.expiresAt,
        DateTime.parse('2026-11-01T09:05:00.000Z').toUtc(),
      );
    });

    test('accepts a replayed 200 as well as a created 201', () async {
      // A retried idempotent request answers 200 with the same payment body,
      // so a cashier who double-pressed gets one payable QR, not two.
      final transport = _Transport(_createdJson, statusCode: 200);
      final payment = await transport.client.createPayment(
        amount: 3.66,
        referenceId: 'T1',
      );
      expect(payment.id, _paymentId);
    });

    test('refuses an answer with no payment id', () async {
      final transport = _Transport('{"status":"paid"}');
      final failure = await _reject(
        transport.client.createPayment(amount: 1, referenceId: 'T1'),
      );
      expect(failure.code, 'unreadable_answer');
    });
  });

  group('getPayment', () {
    test('addresses the payment by id', () async {
      final transport = _Transport(
        '{"id":"$_paymentId","status":"paid","amount":"3.66"}',
        statusCode: 200,
      );
      final payment = await transport.client.getPayment(_paymentId);
      expect(transport.request.method, 'GET');
      expect(transport.request.url.path, '/v1/payments/$_paymentId');
      expect(transport.request.body, isEmpty);
      expect(payment.status, CutluyPaymentStatus.paid);
      expect(payment.amount, 3.66);
    });

    test('encodes an id that is not a path segment', () async {
      final transport = _Transport(
        '{"id":"a/b c","status":"paid"}',
        statusCode: 200,
      );
      await transport.client.getPayment('a/b c');
      expect(transport.request.url.path, '/v1/payments/a%2Fb%20c');
    });

    test('refuses an answer about a different payment', () async {
      // Confirming the wrong sale is the failure this guard exists for: an id
      // that does not match the one asked about is never trusted.
      final transport = _Transport(
        '{"id":"someone_elses_payment","status":"paid","amount":"999.00"}',
        statusCode: 200,
      );
      final failure = await _reject(transport.client.getPayment(_paymentId));
      expect(failure.message, contains('different payment'));
    });
  });

  group('error answers', () {
    test('carries the documented error code and message', () async {
      final transport = _Transport(
        {'error': 'quota_exceeded', 'message': 'Monthly quota reached.'},
        statusCode: 402,
      );
      final failure = await _reject(
        transport.client.createPayment(amount: 1, referenceId: 'T1'),
      );
      expect(failure.httpStatus, 402);
      expect(failure.code, 'quota_exceeded');
      expect(failure.message, 'Monthly quota reached.');
    });

    test('falls back to the status when the body names no error', () async {
      final transport = _Transport({'detail': 'nope'}, statusCode: 413);
      final failure = await _reject(
        transport.client.createPayment(amount: 1, referenceId: 'T1'),
      );
      expect(failure.code, 'http_413');
      expect(failure.message, 'http_413');
    });

    test('reads Retry-After off a rate limit', () async {
      final transport = _Transport(
        {'error': 'rate_limited', 'message': 'Slow down.'},
        statusCode: 429,
        headers: {'retry-after': '37'},
      );
      final failure = await _reject(
        transport.client.createPayment(amount: 1, referenceId: 'T1'),
      );
      expect(failure.code, 'rate_limited');
      expect(failure.retryAfter, const Duration(seconds: 37));
    });

    test('a 429 that gives no wait leaves it unset', () async {
      final transport = _Transport(
        {'error': 'rate_limited'},
        statusCode: 429,
      );
      final failure = await _reject(
        transport.client.createPayment(amount: 1, referenceId: 'T1'),
      );
      expect(failure.retryAfter, isNull);
    });

    test('a non-JSON answer is reported with its status', () async {
      final transport = _Transport('<html>Bad gateway</html>', statusCode: 502);
      final failure = await _reject(transport.client.getPayment(_paymentId));
      expect(failure.httpStatus, 502);
      expect(failure.code, 'unreadable_answer');
      expect(failure.message, contains('not JSON'));
    });

    test('a refusal on creation keeps its own code', () async {
      final transport = _Transport(
        {'error': 'amount_too_low', 'message': 'Minimum is 0.01 USD.'},
        statusCode: 400,
      );
      final failure = await _reject(
        transport.client.createPayment(amount: 0.001, referenceId: 'T1'),
      );
      expect(failure.code, 'amount_too_low');
    });
  });

  group('transport', () {
    test('a call that cannot be made says so as unreachable', () async {
      final failure = await _reject(
        _failing(http.ClientException('no route')).getPayment('p'),
      );
      expect(failure.httpStatus, 503);
      expect(failure.code, 'unreachable');
    });

    test('a call that never answers says so as a timeout', () async {
      final failure = await _reject(
        _failing(TimeoutException('')).getPayment('p'),
      );
      expect(failure.httpStatus, 504);
      expect(failure.code, 'timeout');
    });
  });

  group('configuration', () {
    test('isConfigured depends on the key alone', () {
      expect(
        CutluyClient(
          apiKey: 'ck_live_x',
          baseUrl: 'https://cutluy.com',
        ).isConfigured,
        isTrue,
      );
      expect(
        CutluyClient(apiKey: '', baseUrl: 'https://cutluy.com').isConfigured,
        isFalse,
      );
    });

    test('a trailing slash in the base url does not double the path', () async {
      late http.Request seen;
      final client = CutluyClient(
        client: MockClient((request) async {
          seen = request;
          return http.Response(_createdJson, 201);
        }),
        baseUrl: 'https://cutluy.com///',
        apiKey: 'ck_live_test',
      );
      await client.createPayment(amount: 1, referenceId: 'T1');
      expect(seen.url.toString(), 'https://cutluy.com/v1/payments');
    });
  });

  group('CutluyPaymentStatus.parse', () {
    test('knows the five documented states', () {
      for (final (name, status) in const [
        ('pending', CutluyPaymentStatus.pending),
        ('scanned', CutluyPaymentStatus.scanned),
        ('paid', CutluyPaymentStatus.paid),
        ('expired', CutluyPaymentStatus.expired),
        ('failed', CutluyPaymentStatus.failed),
      ]) {
        expect(CutluyPaymentStatus.parse(name), status);
      }
    });

    test('tolerates case and reports the unfamiliar as unknown', () {
      expect(CutluyPaymentStatus.parse('PAID'), CutluyPaymentStatus.paid);
      expect(CutluyPaymentStatus.parse(null), CutluyPaymentStatus.unknown);
      expect(
        CutluyPaymentStatus.parse('refunded'),
        CutluyPaymentStatus.unknown,
      );
    });
  });

  group('CutluyPayment.fromJson', () {
    test('takes a number as easily as a string for the amount', () {
      expect(
        CutluyPayment.fromJson({'id': 'p', 'amount': 3.5}).amount,
        3.5,
      );
      expect(
        CutluyPayment.fromJson({'id': 'p', 'amount': '3.50'}).amount,
        3.5,
      );
      expect(CutluyPayment.fromJson({'id': 'p', 'amount': 'n/a'}).amount, 0);
      expect(CutluyPayment.fromJson({'id': 'p'}).amount, 0);
    });

    test('defaults what a webhook omits', () {
      final payment = CutluyPayment.fromJson({'id': 'p', 'status': 'paid'});
      expect(payment.currency, 'USD');
      expect(payment.referenceId, '');
      expect(payment.qrString, '');
      expect(payment.checkoutUrl, '');
      expect(payment.approvedAt, isNull);
      expect(payment.expiresAt, isNull);
    });

    test('reads the timestamps it is given', () {
      final payment = CutluyPayment.fromJson({
        'id': 'p',
        'created_at': '2026-11-01T09:00:00Z',
        'approved_at': '2026-11-01T09:02:11.000Z',
        'expires_at': 'not a date',
      });
      expect(payment.createdAt, DateTime.utc(2026, 11, 1, 9));
      expect(payment.approvedAt, DateTime.utc(2026, 11, 1, 9, 2, 11));
      expect(payment.expiresAt, isNull);
    });
  });
}
