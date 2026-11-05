import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

const String _tranId = '2603121000001';

AppConfig _config({
  String merchantId = 'keng.dara.online',
  String apiKey = 'test-api-key',
  String currency = 'KHR',
  Duration lifetime = const Duration(minutes: 10),
  String callbackUrl = '',
  String qrImageTemplate = '',
  String provider = 'payway',
}) => AppConfig(
  mongoUri: 'mongodb://localhost/pos_api_test',
  port: 3000,
  jwtSecret: 'test-secret',
  fileBaseUrl: 'http://localhost:8080',
  paymentProvider: provider,
  paywayBaseUrl: paywaySandboxBaseUrl,
  paywayMerchantId: merchantId,
  paywayApiKey: apiKey,
  paywayCurrency: currency,
  paywayQrLifetime: lifetime,
  paywayCallbackUrl: callbackUrl,
  paywayQrImageTemplate: qrImageTemplate,
);

/// The answer PayWay gives to a successful `generate-qr`.
final Map<String, Object?> _qrSuccess = {
  'qrString': '00020101021230510016abaakhppxxx@abaa520459995303840540515000',
  'qrImage': 'data:image/png;base64,iVBORw0KGgo=',
  'abapay_deeplink': 'abamobilebank://ababank.com?type=payway&qrcode=0002',
  'app_store': 'https://itunes.apple.com/al/app/aba-mobile-bank/id968860649',
  'play_store': 'https://play.google.com/store/apps/details?id=com.paygo24',
  'amount': 15000,
  'currency': 'KHR',
  'status': {'code': '0', 'message': 'Success.', 'trace_id': 'trace-1'},
};

class _Stub {
  _Stub(
    Object body, {
    int statusCode = 200,
    AppConfig? config,
  }) {
    final sent = <http.Request>[];
    final client = PaywayClient(
      client: MockClient((request) async {
        sent.add(request);
        return http.Response(
          body is String ? body : jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'https://checkout-sandbox.payway.com.kh',
      merchantId: (config ?? _config()).paywayMerchantId,
      apiKey: (config ?? _config()).paywayApiKey,
      clock: () => DateTime.utc(2026, 3, 12, 9, 54, 39),
    );
    provider = PaywayProvider(config: config ?? _config(), client: client);
    _sent = sent;
  }

  late final PaywayProvider provider;
  late final List<http.Request> _sent;

  Map<String, dynamic> get json =>
      jsonDecode(_sent.single.body) as Map<String, dynamic>;
}

/// Runs [action] and returns the refusal the gateway raised.
Future<ProviderRejectException> _refused(Future<Object?> action) async {
  try {
    await action;
  } on ProviderRejectException catch (failure) {
    return failure;
  }
  fail('expected the gateway to refuse the request');
}

QrOrder _order({
  double amount = 15000,
  String currency = 'KHR',
  List<OrderItem> items = const [],
}) => QrOrder(
  tranId: _tranId,
  items: items,
  amount: amount,
  currency: currency,
);

void main() {
  group('open', () {
    test(
      'asks for a code in the shop currency and reports what was charged',
      () async {
        final stub = _Stub(_qrSuccess);
        final qr = await stub.provider.open(_order(amount: 15000));
        expect(qr.tranId, _tranId);
        expect(qr.qrString, startsWith('000201010212'));
        expect(qr.chargeAmount, 15000);
        expect(qr.chargeCurrency, 'KHR');
        expect(qr.payUrl, startsWith('abamobilebank://'));
        expect(qr.traceId, 'trace-1');
        // PayWay gives no expiry of its own, so the configured lifetime is the
        // countdown the till shows.
        expect(
          qr.expiresAt
              .difference(
                DateTime.now().toUtc().add(const Duration(minutes: 10)),
              )
              .abs(),
          lessThan(const Duration(seconds: 5)),
        );
        expect(stub.json['tran_id'], _tranId);
        expect(stub.json['currency'], 'KHR');
      },
    );

    test('carries no exchange rate, because nothing was converted', () async {
      final stub = _Stub(_qrSuccess);
      final qr = await stub.provider.open(_order());
      expect(qr.exchangeRate, isNull);
    });

    test(
      'sends the line list as a remark and the transaction id as return params',
      () async {
        final stub = _Stub(_qrSuccess);
        await stub.provider.open(
          _order(
            items: const [
              OrderItem(
                productId: 'p1',
                name: 'Ice Americano',
                unitPrice: 8000,
                qty: 1,
              ),
            ],
          ),
        );
        final remark = stub.json['items'] as String;
        expect(
          jsonDecode(utf8.decode(base64Decode(remark))),
          [
            {'name': 'Ice Americano', 'quantity': 1, 'price': 8000.0},
          ],
        );
        expect(
          jsonDecode(stub.json['return_params'] as String),
          {'tran_id': _tranId},
        );
      },
    );

    test('sends a callback url only when one is configured', () async {
      final bare = _Stub(_qrSuccess);
      await bare.provider.open(_order());
      expect(bare.json.containsKey('callback_url'), isFalse);

      final configured = _Stub(
        _qrSuccess,
        config: _config(callbackUrl: 'https://pos.example.kh/api/v1/x'),
      );
      await configured.provider.open(_order());
      expect(
        utf8.decode(base64Decode(configured.json['callback_url'] as String)),
        'https://pos.example.kh/api/v1/x',
      );
    });

    test('asks for a branded image only when one is configured', () async {
      final plain = _Stub(_qrSuccess);
      await plain.provider.open(_order());
      expect(plain.json.containsKey('qr_image_template'), isFalse);

      final branded = _Stub(
        _qrSuccess,
        config: _config(qrImageTemplate: 'template1_color'),
      );
      await branded.provider.open(_order());
      expect(branded.json['qr_image_template'], 'template1_color');
    });

    test('refuses a fractional riel amount before the call', () async {
      final stub = _Stub(_qrSuccess);
      expect(
        stub.provider.open(_order(amount: 15000.5)),
        throwsA(
          isA<InvalidEntityException>().having(
            (e) => e.details!.first['message']!,
            'detail',
            contains('whole riel'),
          ),
        ),
      );
      expect(stub._sent, isEmpty);
    });

    test('refuses a riel amount under the gateway minimum', () async {
      final stub = _Stub(_qrSuccess);
      expect(
        stub.provider.open(_order(amount: 99)),
        throwsA(
          isA<InvalidEntityException>().having(
            (e) => e.details!.first['message']!,
            'detail',
            contains('100 riel'),
          ),
        ),
      );
      expect(stub._sent, isEmpty);
    });

    test('refuses a cent-less dollar amount', () async {
      final stub = _Stub(_qrSuccess, config: _config(currency: 'USD'));
      expect(
        stub.provider.open(_order(amount: 0, currency: 'USD')),
        throwsA(isA<InvalidEntityException>()),
      );
      expect(stub._sent, isEmpty);
    });

    test('keeps the gateway code when it refuses', () async {
      final stub = _Stub({
        'status': {
          'code': '6',
          'message': 'Not allowed for this merchant',
          'trace_id': 'trace-9',
        },
      });
      final failure = await _refused(stub.provider.open(_order()));
      expect(failure.code, '6');
      expect(failure.message, contains('whitelisted'));
    });

    test('reports a gateway it could not reach as knowing nothing', () async {
      final stub = _Stub('<html>gateway error</html>');
      expect(
        stub.provider.open(_order()),
        throwsA(isA<ProviderTransportException>()),
      );
    });
  });

  group('lookup', () {
    Future<GatewayAnswer> answerFor(String? gatewayStatus) => _Stub({
      'data': {
        'payment_status': gatewayStatus,
        'total_amount': 15000,
        'payment_amount': 15000,
        'payment_currency': 'KHR',
        'apv': 'A1B2C3',
        'transaction_date': '2026-03-12 09:56:02',
        'status': {'code': '00', 'message': 'Success.'},
      },
    }, statusCode: 200).provider.lookup(_tranId);

    test("maps the gateway vocabulary onto the counter's", () async {
      for (final (word, expected) in const [
        ('APPROVED', GatewayStatus.approved),
        ('PENDING', GatewayStatus.pending),
        ('DECLINED', GatewayStatus.declined),
        ('CLOSED', GatewayStatus.expired),
        ('CANCELLED', GatewayStatus.expired),
        ('REFUNDED', GatewayStatus.unknown),
        ('PRE-AUTH', GatewayStatus.unknown),
      ]) {
        final answer = await answerFor(word);
        expect(answer.status, expected, reason: word);
        expect(answer.statusName, word);
      }
    });

    test('an unreadable status is not evidence of anything', () async {
      final answer = await answerFor('TELEPATHY');
      expect(answer.status, GatewayStatus.unknown);
      expect(answer.statusName, 'TELEPATHY');
    });

    test(
      'carries the amounts and the approval code for the audit trail',
      () async {
        final answer = await answerFor('APPROVED');
        expect(answer.chargedAmount, 15000);
        expect(answer.paidAmount, 15000);
        expect(answer.paidCurrency, 'KHR');
        expect(answer.approvalCode, 'A1B2C3');
      },
    );

    test(
      'addresses the transaction by the merchant id, not a gateway id',
      () async {
        final stub = _Stub({
          'data': {
            'payment_status': 'PENDING',
            'status': {'code': '00'},
          },
        });
        await stub.provider.lookup(_tranId, providerRef: 'ignored');
        final sent = jsonDecode(stub._sent.single.body) as Map<String, dynamic>;
        expect(sent['tran_id'], _tranId);
      },
    );

    test(
      'a gateway that has no record of the transaction is a refusal',
      () async {
        final stub = _Stub({
          'status': {'code': '404', 'message': 'Transaction not found'},
        });
        expect(
          stub.provider.lookup(_tranId),
          throwsA(
            isA<ProviderRejectException>().having(
              (e) => e.code,
              'code',
              '404',
            ),
          ),
        );
      },
    );
  });

  group('readNotification', () {
    NotificationPointer pointer(String body) => PaywayProvider(
      config: _config(),
    ).readNotification(rawBody: utf8.encode(body), headers: const {});

    test('reads a JSON notification', () {
      expect(
        pointer('{"tran_id":"$_tranId","status":"APPROVED"}').tranId,
        _tranId,
      );
    });

    test('reads a form-posted notification', () {
      expect(
        pointer('tran_id=$_tranId&status=APPROVED').tranId,
        _tranId,
      );
    });

    test('believes nothing it is told', () {
      // There is no signature on a PayWay delivery, so a pointer is all it can
      // ever be worth — including to a caller that claims the money arrived.
      final claimed = pointer(
        '{"tran_id":"$_tranId","status":"APPROVED","amount":15000}',
      );
      expect(claimed.tranId, _tranId);
      expect(claimed.providerRef, isEmpty);
    });

    test('refuses a delivery with no transaction to look up', () {
      for (final body in [
        '{}',
        '{"status":"APPROVED"}',
        '{"tran_id":""}',
        '{"tran_id":123}',
        'status=APPROVED',
        '"a string"',
        'not json at all',
      ]) {
        expect(
          () => pointer(body),
          throwsA(isA<BadRequestException>()),
          reason: body,
        );
      }
    });
  });

  group('provider shape', () {
    test('names the currency the shelf prices are in', () {
      expect(PaywayProvider(config: _config()).shopCurrency, 'KHR');
      expect(
        PaywayProvider(config: _config(currency: 'USD')).shopCurrency,
        'USD',
      );
    });

    test('needs both credentials and says so', () {
      expect(PaywayProvider(config: _config()).isConfigured, isTrue);
      expect(
        PaywayProvider(config: _config(merchantId: '')).isConfigured,
        isFalse,
      );
      expect(
        PaywayProvider(config: _config(apiKey: '')).isConfigured,
        isFalse,
      );
      expect(
        PaywayProvider(config: _config(apiKey: '')).configurationHint,
        contains('PAYWAY_MERCHANT_ID'),
      );
    });

    test('offers the next number when the gateway already knows this one', () {
      final provider = PaywayProvider(config: _config());
      expect(provider.isDuplicateTransaction(paywayDuplicateTranId), isTrue);
      expect(provider.isDuplicateTransaction('403'), isTrue);
      expect(provider.isDuplicateTransaction('1'), isFalse);
      expect(provider.isDuplicateTransaction(''), isFalse);
    });

    test('is the gateway a config can choose', () {
      expect(defaultPaymentProvider(_config()).name, 'payway');
    });
  });
}
