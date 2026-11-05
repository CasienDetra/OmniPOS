import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// Signed with `test-api-key`. The digests are computed independently of this
/// code — with Python's `hmac` over the same concatenation — so a change to
/// [paywaySignature] that keeps it self-consistent still fails here. The
/// gateway is the only real oracle, and it answers a wrong hash with the
/// single word "Wrong Hash".
const String _apiKey = 'test-api-key';
const String _merchantId = 'keng.dara.online';
const String _reqTime = '20260312095439';
const String _knownQrHash =
    'x/Oj7TAn8B/+lukCT+zsoDza8XBM9XpEB+bW2l6p/0dG'
    'C585LReWHnwd0BUEE19VFAwJFTiN1DsiJdkYvzMRmw==';
const String _knownCheckHash =
    'kGKujCgr/HKk/us1AI1eoe5uZbxKqjPEOx4tIYeOBaBo'
    'Jl1BFCa+CgTD6oAA2w6PiuyN288T9bfLFU3sb/gzNg==';
const String _knownEmptyHash =
    'Yzo7ZpSwSZG8fotTITu1mXTGkSDPXcuSuENdFxyCdTkj'
    'A8CA7IXyAkW9dD1hIj7vt4WXEe4TZzWcAZHcc6X1yA==';

PaywayQrRequest _request({
  String tranId = '1000001',
  double amount = 15000,
  String currency = 'KHR',
  Duration lifetime = const Duration(minutes: 10),
  String? callbackUrl,
  String? firstName,
  String? phone,
  String? qrImageTemplate,
}) => PaywayQrRequest(
  tranId: tranId,
  amount: amount,
  currency: currency,
  lifetime: lifetime,
  callbackUrl: callbackUrl,
  firstName: firstName,
  phone: phone,
  qrImageTemplate: qrImageTemplate,
);

PaywayClient _clientReturning(
  Object body, {
  void Function(Map<String, Object?> sent)? onSend,
  int statusCode = 200,
}) {
  final transport = MockClient((request) async {
    if (onSend != null) {
      onSend(jsonDecode(request.body) as Map<String, Object?>);
    }
    return http.Response(
      body is String ? body : jsonEncode(body),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  return PaywayClient(
    client: transport,
    baseUrl: 'https://checkout-sandbox.payway.com.kh',
    merchantId: _merchantId,
    apiKey: _apiKey,
    clock: () => DateTime.utc(2026, 3, 12, 9, 54, 39),
  );
}

final _qrSuccess = {
  'qrString': '00020101021230510016abaakhppxxx@abaa520459995303840540515000',
  'qrImage': 'data:image/png;base64,iVBORw0KGgo=',
  'abapay_deeplink': 'abamobilebank://ababank.com?type=payway&qrcode=0002',
  'app_store': 'https://itunes.apple.com/al/app/aba-mobile-bank/id968860649',
  'play_store': 'https://play.google.com/store/apps/details?id=com.paygo24',
  'amount': 15000,
  'currency': 'KHR',
  'status': {'code': '0', 'message': 'Success.', 'trace_id': 'trace-1'},
};

final _checkApproved = {
  'data': {
    'payment_status_code': 0,
    'total_amount': 15000,
    'original_amount': 15000,
    'refund_amount': 0,
    'discount_amount': 0,
    'payment_amount': 15000,
    'payment_currency': 'KHR',
    'apv': '544415',
    'payment_status': 'APPROVED',
    'transaction_date': '2026-03-12 16:54:20',
    'status': {'code': '00', 'message': 'Success!', 'tran_id': '1000001'},
  },
};

void main() {
  group('signature', () {
    test('matches a digest computed outside this implementation', () {
      expect(
        paywaySignature(
          [
            _reqTime,
            _merchantId,
            '1000001',
            '15000',
            '',
            'Dara',
            '',
            '',
            '012988776',
            'purchase',
            'abapay_khqr',
            '',
            '',
            'KHR',
            '',
            '',
            '',
            '',
            '600',
            'template3_color',
          ],
          _apiKey,
        ),
        _knownQrHash,
      );
    });

    test('check-transaction signs req_time, merchant_id and tran_id', () {
      expect(
        paywaySignature([_reqTime, _merchantId, '1000001'], _apiKey),
        _knownCheckHash,
      );
    });

    test('an all-empty concatenation still has a stable digest', () {
      expect(
        paywaySignature(List.filled(paywayQrHashOrder.length, ''), _apiKey),
        _knownEmptyHash,
      );
    });
  });

  group('hash field order', () {
    test('is the order PayWay documents, not the body order', () {
      expect(paywayQrHashOrder, [
        'req_time',
        'merchant_id',
        'tran_id',
        'amount',
        'items',
        'first_name',
        'last_name',
        'email',
        'phone',
        'purchase_type',
        'payment_option',
        'callback_url',
        'return_deeplink',
        'currency',
        'custom_fields',
        'return_params',
        'payout',
        'lifetime',
        'qr_image_template',
      ]);
    });

    test('the request supplies a value for every signed field', () {
      final signed = _request().hashValues(
        reqTime: _reqTime,
        merchantId: _merchantId,
      );
      expect(signed.keys.toList(), paywayQrHashOrder);
      expect(signed.values, everyElement(isA<String>()));
    });

    test('absent optional fields hash as empty strings', () {
      final signed = _request().hashValues(
        reqTime: _reqTime,
        merchantId: _merchantId,
      );
      expect(signed['items'], '');
      expect(signed['callback_url'], '');
      expect(signed['phone'], '');
    });

    test('a known request reproduces the documented digest', () {
      final signed = _request(
        firstName: 'Dara',
        phone: '012988776',
        qrImageTemplate: 'template3_color',
        lifetime: const Duration(minutes: 600),
      ).hashValues(reqTime: _reqTime, merchantId: _merchantId);
      expect(signed['first_name'], 'Dara');
      expect(
        paywaySignature(
          [for (final name in paywayQrHashOrder) signed[name]!],
          _apiKey,
        ),
        _knownQrHash,
      );
    });
  });

  group('amount formatting', () {
    test('KHR is whole riel, because decimals are rejected outright', () {
      expect(paywayAmount(15000, 'KHR'), '15000');
      expect(paywayAmount(15000.4, 'KHR'), '15000');
      expect(paywayAmount(9999.6, 'KHR'), '10000');
    });

    test('USD keeps two decimals and drops the zeros PHP would drop', () {
      expect(paywayAmount(1.5, 'USD'), '1.5');
      expect(paywayAmount(1.50, 'USD'), '1.5');
      expect(paywayAmount(0.01, 'USD'), '0.01');
      expect(paywayAmount(10, 'USD'), '10');
      expect(paywayAmount(1234.05, 'USD'), '1234.05');
    });

    test('the body sends the same text that was hashed', () {
      final request = _request(amount: 10, currency: 'USD');
      final values = request.hashValues(
        reqTime: _reqTime,
        merchantId: _merchantId,
      );
      final body = request.body(
        reqTime: _reqTime,
        merchantId: _merchantId,
        hash: 'x',
      );
      expect(values['amount'], '10');
      expect(body['amount'], '10');
    });
  });

  test('req_time is UTC with no separators', () {
    expect(paywayReqTime(DateTime.utc(2026, 3, 12, 9, 54, 39)), _reqTime);
    expect(
      paywayReqTime(
        DateTime.utc(2026, 1, 1, 0, 0, 0).add(const Duration(hours: 26)),
      ),
      '20260102020000',
    );
  });

  group('request guards', () {
    test(
      'a transaction id longer than the gateway allows is refused locally',
      () {
        expect(
          () => _request(tranId: 'x' * 21),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('a lifetime under three minutes is refused locally', () {
      expect(
        () => _request(lifetime: const Duration(minutes: 2)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('an unsupported payment option is refused locally', () {
      expect(
        () => PaywayQrRequest(
          tranId: '1',
          amount: 1,
          currency: 'USD',
          lifetime: const Duration(minutes: 5),
          paymentOption: 'cards',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('generate-qr', () {
    test('sends every signed field plus the hash and parses the QR', () async {
      Map<String, Object?>? sent;
      final client = _clientReturning(
        _qrSuccess,
        onSend: (body) => sent = body,
      );
      final qr = await client.generateQr(
        _request(
          callbackUrl: 'https://pos.example.kh/api/v1/payments/callback',
        ),
      );

      expect(qr.qrString, _qrSuccess['qrString']);
      expect(qr.abapayDeeplink, _qrSuccess['abapay_deeplink']);
      expect(qr.amount, 15000);
      expect(qr.currency, 'KHR');
      expect(qr.traceId, 'trace-1');

      expect(sent!['merchant_id'], _merchantId);
      expect(sent!['req_time'], _reqTime);
      expect(sent!['payment_option'], 'abapay_khqr');
      expect(sent!['currency'], 'KHR');
      expect(sent!['lifetime'], 10);
      // callback_url travels base64-encoded, as the API requires.
      expect(
        base64Decode(sent!['callback_url']! as String),
        utf8.encode('https://pos.example.kh/api/v1/payments/callback'),
      );
      expect(sent!.keys, isNot(contains('items')));
    });

    test('the hash in the body is the hash of the body', () async {
      String? signed;
      final client = _clientReturning(
        _qrSuccess,
        onSend: (body) {
          signed = body['hash']! as String;
        },
      );
      final request = _request();
      await client.generateQr(request);

      final expected = paywaySignature(
        request
            .hashValues(reqTime: _reqTime, merchantId: _merchantId)
            .values
            .toList(),
        _apiKey,
      );
      expect(signed, expected);
    });

    test('a wrong hash is explained, not just reported', () async {
      final client = _clientReturning({
        'status': {'code': '1', 'message': 'Wrong Hash', 'trace_id': 't'},
      });
      expect(
        () => client.generateQr(_request()),
        throwsA(
          isA<PaywayRejectException>()
              .having((e) => e.code, 'code', paywayWrongHash)
              .having(
                (e) => e.message,
                'message',
                contains('PAYWAY_API_KEY'),
              ),
        ),
      );
    });

    test('an unwhitelisted machine says so', () async {
      final client = _clientReturning({
        'status': {
          'code': '6',
          'message': 'Requested Domain is not in whitelist',
        },
      });
      expect(
        () => client.generateQr(_request()),
        throwsA(
          isA<PaywayRejectException>().having(
            (e) => e.message,
            'message',
            contains('whitelisted'),
          ),
        ),
      );
    });

    test('a duplicated transaction id is identifiable for a retry', () async {
      final client = _clientReturning({
        'status': {'code': '4', 'message': 'Duplicated transaction ID'},
      });
      expect(
        () => client.generateQr(_request()),
        throwsA(
          isA<PaywayRejectException>().having(
            (e) => e.code,
            'code',
            paywayDuplicateTranId,
          ),
        ),
      );
    });

    test('a success with no QR string is not success', () async {
      final client = _clientReturning({
        'status': {'code': '0', 'message': 'Success.', 'trace_id': 't'},
      });
      expect(
        () => client.generateQr(_request()),
        throwsA(isA<PaywayRejectException>()),
      );
    });

    test('an answer that is not JSON becomes a transport failure', () async {
      final client = _clientReturning('<html>502 Bad Gateway</html>');
      expect(
        () => client.generateQr(_request()),
        throwsA(isA<PaywayTransportException>()),
      );
    });
  });

  group('check-transaction', () {
    test('reads the status out of the nested envelope', () async {
      Map<String, Object?>? sent;
      final client = _clientReturning(
        _checkApproved,
        onSend: (body) => sent = body,
      );
      final check = await client.checkTransaction('1000001');

      expect(sent!['hash'], _knownCheckHash);
      expect(check.status, PaywayTransactionStatus.approved);
      expect(check.approvalCode, '544415');
      expect(check.totalAmount, 15000);
      expect(check.paymentCurrency, 'KHR');
      expect(check.transactionDate, '2026-03-12 16:54:20');
    });

    test('a transaction the gateway does not know is a rejection', () async {
      final client = _clientReturning({
        'status': {
          'code': '6',
          'message': 'Transaction not found',
          'tran_id': '1000001',
        },
      });
      expect(
        () => client.checkTransaction('1000001'),
        throwsA(
          isA<PaywayRejectException>().having((e) => e.code, 'code', '6'),
        ),
      );
    });

    test('status names from the gateway map onto our own', () {
      const gatewayNames = [
        'APPROVED',
        'PRE-AUTH',
        'REFUNDED',
        'PENDING',
        'DECLINED',
        'CANCELLED',
        'SOMETHING NEW',
      ];
      expect(
        gatewayNames.map(PaywayTransactionStatus.parse).toList(),
        PaywayTransactionStatus.values,
      );
      expect(
        PaywayTransactionStatus.parse('CLOSED'),
        PaywayTransactionStatus.cancelled,
      );
      expect(
        PaywayTransactionStatus.parse(null),
        PaywayTransactionStatus.unknown,
      );
      expect(
        PaywayTransactionStatus.parse('approved'),
        PaywayTransactionStatus.approved,
      );
    });
  });
}
