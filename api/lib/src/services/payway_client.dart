import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// PayWay's `generate-qr` request fields, in the order its HMAC covers them.
///
/// The order is not the order of the JSON body and it is not alphabetical: it
/// is the concatenation written out in PayWay's own PHP sample. A field added
/// to a request must be listed here, or the gateway answers `1: Wrong Hash`
/// and says nothing more. `payway_client_test.dart` pins this list against the
/// documented order so an edit cannot silently reorder it.
const List<String> paywayQrHashOrder = [
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
];

/// `Base64(HMAC-SHA512(concatenated values, api_key))` — the signature every
/// PayWay request carries.
String paywaySignature(List<String> parts, String apiKey) {
  final hmac = Hmac(sha512, utf8.encode(apiKey));
  return base64Encode(hmac.convert(utf8.encode(parts.join())).bytes);
}

/// Request time: UTC, `YYYYMMDDHHmmss`, no separators.
String paywayReqTime(DateTime at) {
  final utc = at.toUtc();
  String pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
  return '${utc.year}${pad(utc.month)}${pad(utc.day)}'
      '${pad(utc.hour)}${pad(utc.minute)}${pad(utc.second)}';
}

/// The amount exactly as PayWay hashes and receives it.
///
/// PayWay hashes the textual amount, and the integrators it documents are PHP,
/// where concatenating a float renders `1.50` as `1.5` and `10.00` as `10`.
/// KHR may not carry decimals at all (gateway code `46`). Both rules are
/// invisible in a Wrong Hash response, so they live here, in one tested
/// function, rather than at each call site.
String paywayAmount(double amount, String currency) {
  if (currency.toUpperCase() == 'KHR') return amount.round().toString();
  return _trimTrailingZeros(amount.toStringAsFixed(2));
}

String _trimTrailingZeros(String text) {
  if (!text.contains('.')) return text;
  var trimmed = text;
  while (trimmed.endsWith('0')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed.endsWith('.')
      ? trimmed.substring(0, trimmed.length - 1)
      : trimmed;
}

/// What the counter needs to show a customer: a code to render and the
/// deeplink to open ABA Mobile with.
class PaywayQr {
  const PaywayQr({
    required this.tranId,
    required this.qrString,
    required this.qrImage,
    required this.abapayDeeplink,
    required this.appStoreUrl,
    required this.playStoreUrl,
    required this.amount,
    required this.currency,
    required this.traceId,
  });

  final String tranId;

  /// The raw EMVCo payload. Rendering this locally is preferable to the
  /// supplied image: it is smaller and it cannot go stale on a cached screen.
  final String qrString;

  /// A base64 PNG, optionally wrapped in one of PayWay's branded templates.
  final String qrImage;
  final String abapayDeeplink;
  final String appStoreUrl;
  final String playStoreUrl;
  final double amount;
  final String currency;
  final String traceId;
}

/// Where a transaction stands at the gateway.
enum PaywayTransactionStatus {
  /// Paid in full. The only status that means money moved.
  approved,

  /// Paid against a hold, not captured. Not used by this integration.
  preAuth,

  /// Fully or partially refunded.
  refunded,

  /// Awaiting the customer.
  pending,

  /// The payer or the gateway refused it.
  declined,

  /// The merchant closed it.
  cancelled,

  /// Anything else, including a gateway we have not seen answer before.
  unknown;

  static PaywayTransactionStatus parse(String? raw) =>
      switch ((raw ?? '').toUpperCase()) {
        'APPROVED' => PaywayTransactionStatus.approved,
        'PRE-AUTH' => PaywayTransactionStatus.preAuth,
        'REFUNDED' => PaywayTransactionStatus.refunded,
        'PENDING' => PaywayTransactionStatus.pending,
        'DECLINED' => PaywayTransactionStatus.declined,
        'CANCELLED' || 'CLOSED' => PaywayTransactionStatus.cancelled,
        _ => PaywayTransactionStatus.unknown,
      };
}

/// A settled answer about one transaction, as far as the gateway knows.
class PaywayTransactionCheck {
  const PaywayTransactionCheck({
    required this.tranId,
    required this.status,
    required this.paymentStatusName,
    this.totalAmount,
    this.paymentAmount,
    this.paymentCurrency,
    this.approvalCode,
    this.transactionDate,
  });

  final String tranId;
  final PaywayTransactionStatus status;

  /// The gateway's own wording, kept for the audit trail.
  final String paymentStatusName;
  final double? totalAmount;
  final double? paymentAmount;
  final String? paymentCurrency;

  /// Six-character approval code printed on the payer's receipt.
  final String? approvalCode;

  /// When the gateway recorded it, as `YYYY-MM-DD HH:MM:SS` in its own time
  /// zone — kept as text because PayWay gives no offset with it.
  final String? transactionDate;
}

/// PayWay refused the request. [code] is the gateway's status code as a
/// string; the ones worth acting on are [paywayDuplicateTranId] and
/// [paywayWrongHash].
class PaywayRejectException implements Exception {
  const PaywayRejectException(this.code, this.message, {this.traceId});

  final String code;
  final String message;
  final String? traceId;

  @override
  String toString() => 'PaywayRejectException($code): $message';
}

/// PayWay could be reached not at all: no route, TLS failure, or no answer
/// before the timeout. Nothing about the transaction is known.
class PaywayTransportException implements Exception {
  const PaywayTransportException(this.message);

  final String message;

  @override
  String toString() => 'PaywayTransportException: $message';
}

/// generate-qr: `4` and `403` both mean this transaction id is already known to
/// the gateway, so the caller can take the next number and try again.
const String paywayDuplicateTranId = '4';

/// generate-qr: `1`. Either the signing key is wrong or the hash was built
/// from values that do not match the body — the usual cause of a first
/// integration not working.
const String paywayWrongHash = '1';

/// Plain-language reading of the gateway codes a POS actually meets. PayWay's
/// responses carry a code and a sentence, and the sentence is written for its
/// support desk, not for a cashier.
const Map<String, String> paywayCodeHints = {
  paywayWrongHash:
      'PayWay rejected the request signature. Check PAYWAY_API_KEY and that '
      'the request was not altered after signing.',
  '6':
      'This machine is not whitelisted by PayWay. Ask the PayWay integration '
      'team to whitelist the public address the api service calls from.',
  '12': 'PayWay does not allow this currency on the merchant profile.',
  '21': 'The PayWay API subscription for this merchant has ended.',
  '23': 'This merchant profile has no QR payment option enabled.',
  '44':
      'The payment is above the per-transaction limit on the merchant '
      'profile.',
  '46': 'KHR amounts must be whole riel.',
  '47': 'KHR payments must be at least 100 riel.',
  paywayDuplicateTranId: 'PayWay already knows this transaction id.',
  '403': 'PayWay already knows this transaction id.',
  '81': 'The callback URL is not in the merchant profile whitelist.',
  '429': 'PayWay rate limit reached; try again shortly.',
};

/// A payment request, described once and then sent.
///
/// The values are held in the gateway's own field names so that the hash and
/// the JSON body read the same map: the two cannot disagree about what was
/// signed, which is the failure this class exists to prevent.
class PaywayQrRequest {
  PaywayQrRequest({
    required this.tranId,
    required this.amount,
    required this.currency,
    required this.lifetime,
    this.paymentOption = 'abapay_khqr',
    this.purchaseType = 'purchase',
    this.callbackUrl,
    this.items,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.customFields,
    this.returnParams,
    this.qrImageTemplate,
  }) {
    if (paymentOption != 'abapay_khqr' &&
        paymentOption != 'wechat' &&
        paymentOption != 'alipay') {
      throw ArgumentError.value(paymentOption, 'paymentOption');
    }
    if (tranId.length > 20) {
      throw ArgumentError.value(
        tranId,
        'tranId',
        'PayWay allows 20 characters',
      );
    }
    if (lifetime.inMinutes < 3) {
      throw ArgumentError.value(
        lifetime,
        'lifetime',
        'PayWay refuses lifetimes under 3 minutes',
      );
    }
  }

  /// PayWay's own transaction reference: unique per merchant, at most 20
  /// bytes. It is also the idempotency key for everything downstream.
  final String tranId;
  final double amount;
  final String currency;
  final Duration lifetime;
  final String paymentOption;
  final String purchaseType;

  /// Sent base64-encoded, as the API requires.
  final String? callbackUrl;

  /// Base64 of a JSON array of `{name, quantity, price}`. A remark for the
  /// gateway's reports — PayWay ignores the numbers in it.
  final String? items;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final Map<String, Object?>? customFields;

  /// Echoed back verbatim on the notification, so it is how a callback finds
  /// its own payment without trusting `tran_id` alone.
  final String? returnParams;
  final String? qrImageTemplate;

  /// The signed values, in [paywayQrHashOrder]. Absent optional fields are
  /// present as the empty string, matching the PHP samples PayWay documents.
  Map<String, String> hashValues({
    required String reqTime,
    required String merchantId,
  }) {
    final values = bodyValues(reqTime: reqTime, merchantId: merchantId);
    return {
      for (final name in paywayQrHashOrder) name: _forHash(values[name]),
    };
  }

  /// The JSON body: the same values, with nulls left out and numbers kept as
  /// numbers.
  Map<String, Object?> body({
    required String reqTime,
    required String merchantId,
    required String hash,
  }) {
    final values = bodyValues(reqTime: reqTime, merchantId: merchantId);
    return {
      for (final entry in values.entries)
        if (entry.value != null) entry.key: entry.value,
      'hash': hash,
    };
  }

  Map<String, Object?> bodyValues({
    required String reqTime,
    required String merchantId,
  }) => {
    'req_time': reqTime,
    'merchant_id': merchantId,
    'tran_id': tranId,
    // Sent as the same text that is hashed. PayWay documents a PHP sample
    // where the form post and the hash see one identical string, and a JSON
    // number cannot promise that: Dart would write 10.00 as `10.0` where the
    // hash says `10`. If the gateway ever answers `3: Invalid transaction
    // amount`, this is the line to turn back into a number.
    'amount': paywayAmount(amount, currency),
    'items': items,
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'phone': phone,
    'purchase_type': purchaseType,
    'payment_option': paymentOption,
    'callback_url': callbackUrl == null
        ? null
        : base64Encode(utf8.encode(callbackUrl!)),
    'return_deeplink': null,
    'currency': currency.toUpperCase(),
    'custom_fields': customFields == null
        ? null
        : base64Encode(utf8.encode(jsonEncode(customFields))),
    'return_params': returnParams,
    'payout': null,
    'lifetime': lifetime.inMinutes,
    'qr_image_template': qrImageTemplate,
  };

  static String _forHash(Object? value) {
    // An omitted optional field hashes as the empty string, which is what
    // concatenating a null does in the PHP samples PayWay documents.
    return value == null ? '' : '$value';
  }
}

/// HTTP client for the ABA PayWay QR API.
///
/// Only two calls exist on this seam: ask for a QR, and ask whether a
/// transaction got paid. The second is not a convenience — PayWay's payment
/// notification carries no signature, so a notification is a hint to go and
/// check, never a reason to record money as received.
class PaywayClient {
  PaywayClient({
    http.Client? client,
    String? baseUrl,
    String? merchantId,
    String? apiKey,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? AppConfig.current.paywayBaseUrl,
       _merchantId = merchantId ?? AppConfig.current.paywayMerchantId,
       _apiKey = apiKey ?? AppConfig.current.paywayApiKey,
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final String _baseUrl;
  final String _merchantId;
  final String _apiKey;
  final DateTime Function() _clock;

  static const _generateQrPath = '/api/payment-gateway/v1/payments/generate-qr';
  static const _checkPath =
      '/api/payment-gateway/v1/payments/'
      'check-transaction-2';

  bool get isConfigured => _merchantId.isNotEmpty && _apiKey.isNotEmpty;

  /// Generate a dynamic KHQR for a cashier to display.
  Future<PaywayQr> generateQr(PaywayQrRequest request) async {
    final reqTime = paywayReqTime(_clock());
    final hashValues = request.hashValues(
      reqTime: reqTime,
      merchantId: _merchantId,
    );
    final hash = paywaySignature(
      [for (final name in paywayQrHashOrder) hashValues[name]!],
      _apiKey,
    );
    final body = request.body(
      reqTime: reqTime,
      merchantId: _merchantId,
      hash: hash,
    );

    final response = await _post(_generateQrPath, body);
    final status = _statusOf(response);
    if (status.code != '0') {
      throw _reject(status);
    }
    final qrString = response['qrString'];
    if (qrString is! String || qrString.isEmpty) {
      throw const PaywayRejectException(
        '8',
        'PayWay answered with no QR string.',
      );
    }
    return PaywayQr(
      tranId: request.tranId,
      qrString: qrString,
      qrImage: response['qrImage'] as String? ?? '',
      abapayDeeplink: response['abapay_deeplink'] as String? ?? '',
      appStoreUrl: response['app_store'] as String? ?? '',
      playStoreUrl: response['play_store'] as String? ?? '',
      amount: (response['amount'] as num?)?.toDouble() ?? request.amount,
      currency: response['currency'] as String? ?? request.currency,
      traceId: status.traceId,
    );
  }

  /// Ask the gateway what became of a transaction. Only transactions created
  /// within the last seven days answer; older ones are [PaywayRejectException]
  /// with the gateway's own message.
  Future<PaywayTransactionCheck> checkTransaction(String tranId) async {
    final reqTime = paywayReqTime(_clock());
    final response = await _post(_checkPath, {
      'req_time': reqTime,
      'merchant_id': _merchantId,
      'tran_id': tranId,
      'hash': paywaySignature(
        [reqTime, _merchantId, tranId],
        _apiKey,
      ),
    });
    // A confirmed transaction answers `{data: {…, status: {…}}}` — the status
    // sits inside the payload. Only a rejection answers `{status: {…}}` at the
    // top level. Both shapes have to be read or a paid sale looks like a
    // malformed answer.
    final data = response['data'];
    final statusNode =
        response['status'] ?? (data is Map ? data['status'] : null);
    final status = statusNode is Map
        ? _GatewayStatus.parse(Map<String, dynamic>.from(statusNode))
        : const _GatewayStatus(
            code: '8',
            message: 'Malformed gateway answer',
          );
    if (status.code != '00') throw _reject(status);

    if (data is! Map) {
      throw PaywayRejectException(
        status.code,
        'PayWay confirmed the request but returned no transaction data.',
        traceId: status.traceId,
      );
    }
    final record = Map<String, dynamic>.from(data);
    return PaywayTransactionCheck(
      tranId: tranId,
      status: PaywayTransactionStatus.parse(
        record['payment_status'] as String?,
      ),
      paymentStatusName: record['payment_status'] as String? ?? '',
      totalAmount: (record['total_amount'] as num?)?.toDouble(),
      paymentAmount: (record['payment_amount'] as num?)?.toDouble(),
      paymentCurrency: record['payment_currency'] as String?,
      approvalCode: record['apv'] as String?,
      transactionDate: record['transaction_date'] as String?,
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const PaywayTransportException(
        'PayWay did not answer within 20 seconds',
      );
    } on Exception {
      throw const PaywayTransportException('PayWay could not be reached');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      throw PaywayTransportException(
        'PayWay answered ${response.statusCode} with something that is not '
        'JSON',
      );
    }
    return Map<String, dynamic>.from(decoded);
  }

  _GatewayStatus _statusOf(Map<String, dynamic> response) {
    final status = response['status'];
    if (status is Map) {
      return _GatewayStatus.parse(Map<String, dynamic>.from(status));
    }
    return const _GatewayStatus(
      code: '8',
      message: 'PayWay gave no status for this request',
    );
  }

  PaywayRejectException _reject(_GatewayStatus status) {
    final hint = paywayCodeHints[status.code];
    final message = hint == null
        ? 'PayWay: ${status.message}'
        : 'PayWay: ${status.message} — $hint';
    return PaywayRejectException(status.code, message, traceId: status.traceId);
  }

  void close() => _client.close();
}

class _GatewayStatus {
  const _GatewayStatus({
    required this.code,
    required this.message,
    this.traceId = '',
  });

  final String code;
  final String message;
  final String traceId;

  static _GatewayStatus parse(Map<String, dynamic> status) => _GatewayStatus(
    // generate-qr reports success as "0" and check-transaction as "00"; either
    // way the code can arrive as a number or a string.
    code: '${status['code'] ?? ''}',
    message: status['message'] as String? ?? '',
    traceId: status['trace_id'] as String? ?? '',
  );
}
