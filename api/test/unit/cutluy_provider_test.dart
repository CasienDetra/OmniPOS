import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// The endpoint secret the tests sign deliveries with.
const String _secret = 'whsec_test_secret';

const String _tranId = '2603121000001';
const String _paymentId = 'PUETcMUOKStjZsCb6zAl8kg9fMRGM85x';

OrderItem _line(double unitPrice, {int qty = 1}) => OrderItem(
  productId: 'p',
  name: 'Item',
  unitPrice: unitPrice,
  qty: qty,
);

AppConfig _config({
  String apiKey = 'ck_live_test',
  String webhookSecret = _secret,
  double khrUsdRate = 4100,
  String shopCurrency = 'KHR',
  String provider = 'cutluy',
  Duration webhookTolerance = const Duration(minutes: 5),
  Duration fallbackExpiry = const Duration(minutes: 5),
}) => AppConfig(
  mongoUri: 'mongodb://localhost/pos_api_test',
  port: 3000,
  jwtSecret: 'test-secret',
  fileBaseUrl: 'http://localhost:8080',
  paymentProvider: provider,
  paywayBaseUrl: paywaySandboxBaseUrl,
  paywayMerchantId: '',
  paywayApiKey: '',
  paywayCurrency: 'KHR',
  paywayQrLifetime: const Duration(minutes: 10),
  paywayCallbackUrl: '',
  paywayQrImageTemplate: '',
  cutluyApiKey: apiKey,
  cutluyWebhookSecret: webhookSecret,
  cutluyKhrUsdRate: khrUsdRate,
  cutluyShopCurrency: shopCurrency,
  cutluyWebhookTolerance: webhookTolerance,
  cutluyFallbackExpiry: fallbackExpiry,
);

/// A provider wired to a transport that answers with a fixed body, plus the
/// requests it was given.
class _Stub {
  _Stub(
    Object body, {
    int statusCode = 201,
    Map<String, String> responseHeaders = const {},
    AppConfig? config,
  }) {
    final sent = <http.Request>[];
    final client = CutluyClient(
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json', ...responseHeaders},
        );
      }),
      baseUrl: 'https://cutluy.com',
      apiKey: (config ?? _config()).cutluyApiKey,
    );
    provider = CutluyProvider(config: config ?? _config(), client: client);
    _sent = sent;
  }

  late final CutluyProvider provider;
  late final List<http.Request> _sent;

  Map<String, dynamic> get json =>
      jsonDecode(_sent.single.body) as Map<String, dynamic>;
}

/// A payment as CutLuy answers it, with the fields a test cares about.
String _paymentJson({
  String status = 'pending',
  String amount = '3.66',
  String referenceId = _tranId,
  String id = _paymentId,
  String qrString = '00020101021226580017com.example.qr',
  String? approvedAt,
  String? expiresAt,
}) {
  final fields = <String, Object?>{
    'id': id,
    'status': status,
    'amount': amount,
    'currency': 'USD',
    'reference_id': referenceId,
    'qr_string': qrString,
    'checkout_url': 'https://pay.example.kh/p/$id',
    'created_at': '2026-11-01T09:00:00.000Z',
  };
  if (approvedAt != null) fields['approved_at'] = approvedAt;
  if (expiresAt != null) fields['expires_at'] = expiresAt;
  return jsonEncode(fields);
}

/// A `payment.completed` event body for [_tranId].
String _eventBody({String type = 'payment.completed', String status = 'paid'}) {
  return jsonEncode({
    'id': 'evt_2a',
    'type': type,
    'created': '2026-11-01T09:00:00.000Z',
    'data': {
      'payment': {
        'id': _paymentId,
        'status': status,
        'amount': '3.66',
        'currency': 'USD',
        'reference_id': _tranId,
        'metadata': null,
        'approved_at': '2026-11-01T09:02:11.000Z',
      },
    },
  });
}

/// Signs [body] the way CutLuy does: `t=<unix>,v1=<hex hmac over "t.body">`.
Map<String, String> _delivered(
  String body, {
  int? atSeconds,
  String secret = _secret,
}) {
  final seconds =
      atSeconds ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
  return {
    'x-cutluy-event': 'payment.completed',
    'x-cutluy-signature':
        't=$seconds,v1=${webhookDigestHex(
          secret: secret,
          rawBody: utf8.encode(body),
          timestamp: seconds,
        )}',
  };
}

int get _nowSeconds => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;

QrOrder _order({
  double amount = 15000,
  String currency = 'KHR',
  List<OrderItem>? items,
}) => QrOrder(
  tranId: _tranId,
  items: items ?? [_line(amount, qty: 1)],
  amount: amount,
  currency: currency,
);

void main() {
  group('usdChargeTotal', () {
    test('converts each line and adds the cents up', () {
      // 4100 riel is exactly a dollar, 2050 half of one, and 683 riel is
      // 16.66 cents — which is charged as 17 because the till showed 17.
      final total = usdChargeTotal([
        _line(4100),
        _line(2050),
        _line(683),
      ], 4100);
      expect(total, 1.67);
    });

    test('rounds the lines, not the sum', () {
      // Three lines of 100 riel are 2 cents each at 4100, so the cashier can
      // add 0.02 + 0.02 + 0.02. Rounding the total instead would ask for 0.07.
      expect(usdChargeTotal([_line(100), _line(100), _line(100)], 4100), 0.06);
      expect(usdChargeTotal([_line(100, qty: 3)], 4100), 0.07);
    });

    test('multiplies the line before converting it', () {
      expect(usdChargeTotal([_line(4100, qty: 3)], 4100), 3.00);
    });

    test('leaves the amount alone at a rate of one', () {
      expect(usdChargeTotal([_line(10.5), _line(2.25)], 1), 12.75);
    });

    test('is zero for an empty cart', () {
      expect(usdChargeTotal(const [], 4100), 0.0);
    });

    test('does not divide the dollars by the rate a second time', () {
      // The shape a regression takes: a 12,000 riel cart at 4000 must cost
      // three dollars, not a tenth of a cent.
      expect(usdChargeTotal([_line(12000)], 4000), 3.0);
    });
  });

  group('open', () {
    test('charges the converted cart and keeps both figures', () async {
      final stub = _Stub(
        _paymentJson(amount: '3.66', expiresAt: '2026-11-01T09:05:00.000Z'),
      );
      final qr = await stub.provider.open(_order(amount: 15000));
      expect(qr.tranId, _tranId);
      expect(qr.qrString, startsWith('000201010212'));
      expect(qr.chargeAmount, 3.66);
      expect(qr.chargeCurrency, 'USD');
      expect(qr.exchangeRate, 4100);
      expect(qr.providerRef, _paymentId);
      expect(qr.checkoutUrl, contains(_paymentId));
      expect(
        qr.expiresAt,
        DateTime.parse('2026-11-01T09:05:00.000Z').toUtc(),
      );
      expect(stub.json['amount'], 3.66);
      expect(stub.json['reference_id'], _tranId);
    });

    test('sends the shop money in metadata for the gateway reports', () async {
      final stub = _Stub(_paymentJson());
      await stub.provider.open(_order(amount: 15000));
      expect(stub.json['metadata'], {
        'pos_currency': 'KHR',
        'pos_total': 15000.0,
        'exchange_rate': 4100.0,
      });
    });

    test('prices a USD shop without converting', () async {
      final stub = _Stub(
        _paymentJson(amount: '12.00'),
        config: _config(shopCurrency: 'USD', khrUsdRate: 0),
      );
      final qr = await stub.provider.open(
        _order(amount: 12, currency: 'USD'),
      );
      expect(stub.json['amount'], 12.0);
      expect(qr.chargeAmount, 12.0);
      expect(qr.exchangeRate, isNull);
    });

    test('refuses a cart worth less than a cent', () async {
      final stub = _Stub(
        _paymentJson(amount: '0.00'),
        config: _config(khrUsdRate: 4100),
      );
      expect(
        stub.provider.open(_order(amount: 1)),
        throwsA(isA<InvalidEntityException>()),
      );
      expect(stub._sent, isEmpty);
    });

    test('refuses to guess a rate for a KHR shop', () async {
      final stub = _Stub(_paymentJson(), config: _config(khrUsdRate: 0));
      await expectLater(
        stub.provider.open(_order()),
        throwsA(
          isA<ServiceUnavailableException>().having(
            (e) => e.error,
            'error',
            contains('CUTLUY_KHR_USD_RATE'),
          ),
        ),
      );
      expect(stub._sent, isEmpty);
    });

    test(
      'falls back to a configured expiry when the answer has none',
      () async {
        final stub = _Stub(
          _paymentJson(),
          config: _config(fallbackExpiry: const Duration(minutes: 7)),
        );
        final qr = await stub.provider.open(_order());
        final expected = DateTime.now().toUtc().add(
          const Duration(minutes: 7),
        );
        expect(
          qr.expiresAt.difference(expected).abs(),
          lessThan(const Duration(seconds: 5)),
        );
      },
    );

    test('refuses a payment that came back with no QR', () async {
      final stub = _Stub(_paymentJson(qrString: ''));
      expect(
        stub.provider.open(_order()),
        throwsA(
          isA<ProviderRejectException>().having(
            (e) => e.code,
            'code',
            'no_qr',
          ),
        ),
      );
    });

    test("refuses a payment for someone else's transaction", () async {
      // The reference id is the only thing tying a gateway payment to a sale
      // opened at this till, so a mismatch is never adopted.
      final stub = _Stub(_paymentJson(referenceId: 'other_till'));
      expect(
        stub.provider.open(_order()),
        throwsA(
          isA<ProviderRejectException>().having(
            (e) => e.code,
            'code',
            'reference_mismatch',
          ),
        ),
      );
    });

    test('translates a refusal into something a cashier can act on', () async {
      final stub = _Stub(
        {'error': 'account_suspended', 'message': 'Account suspended.'},
        statusCode: 403,
      );
      expect(
        stub.provider.open(_order()),
        throwsA(
          isA<ProviderUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('suspended'),
          ),
        ),
      );
    });
  });

  group('lookup', () {
    test('needs the gateway id for the payment', () async {
      final stub = _Stub(_paymentJson());
      expect(
        stub.provider.lookup(_tranId),
        throwsA(
          isA<ProviderRejectException>().having(
            (e) => e.code,
            'code',
            'no_provider_ref',
          ),
        ),
      );
      expect(stub._sent, isEmpty);
    });

    test('maps each status the gateway reports', () async {
      for (final (name, expected) in const [
        ('paid', GatewayStatus.approved),
        ('scanned', GatewayStatus.scanned),
        ('pending', GatewayStatus.pending),
        ('expired', GatewayStatus.expired),
        ('failed', GatewayStatus.declined),
        ('refunded', GatewayStatus.unknown),
      ]) {
        final stub = _Stub(
          _paymentJson(status: name),
          statusCode: 200,
        );
        final answer = await stub.provider.lookup(
          _tranId,
          providerRef: _paymentId,
        );
        expect(answer.status, expected, reason: name);
        expect(answer.statusName, name);
        expect(answer.tranId, _tranId);
      }
    });

    test('carries the money and the moment it settled', () async {
      final stub = _Stub(
        _paymentJson(
          status: 'paid',
          amount: '3.66',
          approvedAt: '2026-11-01T09:02:11.000Z',
        ),
        statusCode: 200,
      );
      final answer = await stub.provider.lookup(
        _tranId,
        providerRef: _paymentId,
      );
      expect(answer.chargedAmount, 3.66);
      expect(answer.chargedCurrency, 'USD');
      expect(answer.providerRef, _paymentId);
      expect(answer.message, isEmpty);
    });

    test('says so when the payment failed', () async {
      final stub = _Stub(_paymentJson(status: 'failed'), statusCode: 200);
      final answer = await stub.provider.lookup(
        _tranId,
        providerRef: _paymentId,
      );
      expect(answer.message, contains('failed'));
    });

    test('refuses an answer whose reference belongs to another sale', () async {
      final stub = _Stub(
        _paymentJson(status: 'paid', referenceId: 'someone_else'),
        statusCode: 200,
      );
      expect(
        stub.provider.lookup(_tranId, providerRef: _paymentId),
        throwsA(
          isA<ProviderRejectException>().having(
            (e) => e.code,
            'code',
            'reference_mismatch',
          ),
        ),
      );
    });

    test('addresses the payment by its gateway id', () async {
      final stub = _Stub(_paymentJson(), statusCode: 200);
      await stub.provider.lookup(_tranId, providerRef: _paymentId);
      expect(stub._sent.single.method, 'GET');
      expect(stub._sent.single.url.path, '/v1/payments/$_paymentId');
    });
  });

  group('readNotification', () {
    test('accepts a signed delivery and points at the transaction', () {
      final provider = CutluyProvider(config: _config());
      final body = _eventBody();
      final pointer = provider.readNotification(
        rawBody: utf8.encode(body),
        headers: _delivered(body),
      );
      expect(pointer.tranId, _tranId);
      expect(pointer.providerRef, _paymentId);
    });

    test('points at the same transaction for any event type', () {
      // The type is not read as evidence. `payment.scanned` and
      // `payment.completed` both mean "go and look", and only the looked-up
      // answer decides whether a Sale is written.
      final provider = CutluyProvider(config: _config());
      for (final type in [
        'payment.scanned',
        'payment.completed',
        'payment.expired',
        'payment.failed',
      ]) {
        final body = _eventBody(type: type, status: 'pending');
        expect(
          provider
              .readNotification(
                rawBody: utf8.encode(body),
                headers: _delivered(body),
              )
              .tranId,
          _tranId,
          reason: type,
        );
      }
    });

    test('refuses a delivery with no signature when a secret is set', () {
      final provider = CutluyProvider(config: _config());
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(_eventBody()),
          headers: const {},
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('refuses every unsigned delivery, whatever it claims', () {
      // An unauthenticated caller can otherwise write money into the books by
      // POSTing a plausible-looking event.
      final provider = CutluyProvider(config: _config());
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(_eventBody()),
          headers: {'x-cutluy-signature': 't=1,v1=deadbeef'},
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test("refuses a delivery signed with someone else's secret", () {
      final provider = CutluyProvider(config: _config());
      final body = _eventBody();
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body, secret: 'whsec_not_ours'),
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('refuses a body edited after it was signed', () {
      final provider = CutluyProvider(config: _config());
      final signed = _eventBody();
      final headers = _delivered(signed);
      final tampered = signed.replaceAll(_tranId, '2603121000002');
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(tampered),
          headers: headers,
        ),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('refuses a stale delivery even though its signature is correct', () {
      final provider = CutluyProvider(config: _config());
      final body = _eventBody();
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body, atSeconds: _nowSeconds - 400),
        ),
        throwsA(
          isA<UnauthorizedException>().having(
            (e) => e.error,
            'error',
            contains('timestamp'),
          ),
        ),
      );
    });

    test('accepts a delivery inside a widened window', () {
      final provider = CutluyProvider(
        config: _config(webhookTolerance: const Duration(minutes: 10)),
      );
      final body = _eventBody();
      expect(
        provider
            .readNotification(
              rawBody: utf8.encode(body),
              headers: _delivered(body, atSeconds: _nowSeconds - 400),
            )
            .tranId,
        _tranId,
      );
    });

    test('refuses a signature header that is not in the documented shape', () {
      final provider = CutluyProvider(config: _config());
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(_eventBody()),
          headers: {'x-cutluy-signature': 'not-a-signature'},
        ),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('refuses notifications outright with no endpoint secret', () {
      final provider = CutluyProvider(config: _config(webhookSecret: ''));
      final body = _eventBody();
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body),
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });

    test('refuses a signed body that is not JSON', () {
      final provider = CutluyProvider(config: _config());
      const body = '<html>not an event</html>';
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body),
        ),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('refuses an event with no payment in it', () {
      final provider = CutluyProvider(config: _config());
      const body = '{"id":"evt_1","type":"payment.completed","data":{}}';
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body),
        ),
        throwsA(isA<BadRequestException>()),
      );
    });

    test('refuses a payment with no reference to match on', () {
      // Without the POS transaction id there is nothing to go and look up, and
      // guessing from the gateway id would confirm an arbitrary sale.
      final provider = CutluyProvider(config: _config());
      const body =
          '{"data":{"payment":{"id":"p1","status":"paid","amount":"1.00"}}}';
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(body),
          headers: _delivered(body),
        ),
        throwsA(isA<BadRequestException>()),
      );
    });
  });

  group('cutluyFailure', () {
    /// Drives one answer through the provider and reports what it raised.
    Future<Object> raised(
      int httpStatus,
      String code, {
      Duration? retryAfter,
    }) async {
      final stub = _Stub(
        {'error': code, 'message': 'the gateway said $code'},
        statusCode: httpStatus,
        responseHeaders: retryAfter == null
            ? const {}
            : {'retry-after': '${retryAfter.inSeconds}'},
      );
      try {
        await stub.provider.open(_order());
      } catch (failure) {
        return failure;
      }
      fail('expected the $httpStatus $code answer to be refused');
    }

    test(
      'an unauthorised key is a configuration problem, not a bad sale',
      () async {
        expect(
          await raised(401, 'unauthorized'),
          isA<ProviderUnavailableException>(),
        );
      },
    );

    test('a spent quota names what to check', () async {
      final failure =
          await raised(402, 'quota_exceeded') as ProviderUnavailableException;
      expect(failure.message, contains('/v1/usage'));
    });

    test('a suspended account is unavailable until it is settled', () async {
      expect(
        await raised(403, 'account_suspended'),
        isA<ProviderUnavailableException>(),
      );
    });

    test('a missing payment link is named', () async {
      for (final (status, code) in const [
        (404, 'payment_link_not_found'),
        (400, 'payment_link_disabled'),
      ]) {
        final failure = await raised(status, code);
        expect(
          failure,
          isA<ProviderUnavailableException>(),
          reason: '$status $code',
        );
        expect(
          (failure as ProviderUnavailableException).message,
          contains('payment link'),
          reason: '$status $code',
        );
      }
    });

    test('a rate limit passes the wait through', () async {
      final failure =
          await raised(
                429,
                'rate_limited',
                retryAfter: const Duration(seconds: 30),
              )
              as ProviderUnavailableException;
      expect(failure.retryAfter, const Duration(seconds: 30));
      expect(failure.message, contains('60 creations'));
    });

    test(
      "an amount the gateway will not take is the caller's error",
      () async {
        for (final code in const [
          'invalid_amount',
          'amount_too_low',
          'amount_too_high',
        ]) {
          expect(
            await raised(400, code),
            isA<InvalidEntityException>(),
            reason: code,
          );
        }
      },
    );

    test('a gateway that could not be reached knows nothing', () async {
      for (final status in const [500, 502, 503, 504]) {
        expect(
          await raised(status, 'payment_provider_error'),
          isA<ProviderTransportException>(),
          reason: '$status',
        );
      }
    });

    test('anything else is a refusal with a code attached', () async {
      for (final (status, code) in const [
        (405, 'method_not_allowed'),
        (413, 'payload_too_large'),
        (404, 'payment_not_found'),
      ]) {
        final failure = await raised(status, code);
        expect(
          failure,
          isA<ProviderRejectException>(),
          reason: '$status $code',
        );
        expect(
          (failure as ProviderRejectException).code,
          code,
          reason: '$status $code',
        );
      }
    });

    test('a name that is not a gateway answers 503 with what was written', () {
      const provider = MisconfiguredProvider('stripe');
      expect(provider.isConfigured, isFalse);
      expect(provider.configurationHint, contains('"stripe"'));
      expect(
        () => provider.open(_order()),
        throwsA(isA<ServiceUnavailableException>()),
      );
      expect(
        () => provider.readNotification(
          rawBody: utf8.encode(_eventBody()),
          headers: _delivered(_eventBody()),
        ),
        throwsA(isA<ServiceUnavailableException>()),
      );
    });
  });

  group('provider shape', () {
    test('reports what to set when the key is missing', () {
      final provider = CutluyProvider(config: _config(apiKey: ''));
      expect(provider.isConfigured, isFalse);
      expect(provider.configurationHint, contains('CUTLUY_API_KEY'));
    });

    test('reports what to set when a KHR shop has no rate', () {
      final provider = CutluyProvider(config: _config(khrUsdRate: 0));
      expect(provider.isConfigured, isFalse);
      expect(provider.configurationHint, contains('CUTLUY_KHR_USD_RATE'));
    });

    test('a key alone is enough for a USD shop', () {
      final provider = CutluyProvider(
        config: _config(shopCurrency: 'USD', khrUsdRate: 0),
      );
      expect(provider.isConfigured, isTrue);
    });

    test('names the currency the shelf prices are in', () {
      expect(CutluyProvider(config: _config()).shopCurrency, 'KHR');
    });

    test('never treats a repeated transaction id as a collision', () {
      // The id doubles as the idempotency key, so a repeat returns the same
      // payment instead of being refused.
      expect(
        CutluyProvider(config: _config()).isDuplicateTransaction('4'),
        isFalse,
      );
    });

    test('the routes drive whichever gateway the config names', () {
      expect(defaultPaymentProvider(_config()).name, 'cutluy');
      expect(
        defaultPaymentProvider(_config(provider: 'payway')).name,
        'payway',
      );
      expect(
        defaultPaymentProvider(_config(provider: 'CUTLUY')).name,
        'cutluy',
      );
      expect(
        defaultPaymentProvider(_config(provider: 'stripe')).name,
        'stripe',
      );
    });
  });
}
