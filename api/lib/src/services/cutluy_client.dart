import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// The states CutLuy reports for a payment. `paid`, `expired` and `failed` are
/// terminal; `pending` and `scanned` are not, and neither of them is money.
enum CutluyPaymentStatus {
  pending,
  scanned,
  paid,
  expired,
  failed,

  /// A status CutLuy reports that this build does not know. It is neither money
  /// nor a failure, so it is waited on rather than guessed at.
  unknown;

  static CutluyPaymentStatus parse(String? raw) {
    final name = (raw ?? '').toLowerCase();
    return values.firstWhere(
      (status) => status.name == name,
      orElse: () => CutluyPaymentStatus.unknown,
    );
  }
}

/// A payment as CutLuy describes it.
class CutluyPayment {
  const CutluyPayment({
    required this.id,
    required this.status,
    required this.amount,
    required this.currency,
    required this.createdAt,
    this.statusName = '',
    this.referenceId = '',
    this.qrString = '',
    this.checkoutUrl = '',
    this.approvedAt,
    this.expiresAt,
  });

  /// CutLuy's id for the payment. It is what a webhook and every later read are
  /// addressed with, and what the hosted checkout page is built from.
  final String id;
  final CutluyPaymentStatus status;

  /// The status word CutLuy used, kept because an unfamiliar one parses to
  /// `unknown` and the audit trail has to say what was actually reported.
  final String statusName;

  /// A decimal string on the wire ("1.50"), read here as a number.
  final double amount;
  final String currency;

  /// The POS's own transaction id, sent as `reference_id` and echoed back.
  final String referenceId;

  /// The raw EMVCo payload. Present on create; a later read is about status.
  final String qrString;
  final String checkoutUrl;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? expiresAt;

  static CutluyPayment fromJson(Map<String, dynamic> json) {
    final created = _time(json['created_at']);
    final expires = _time(json['expires_at']);
    return CutluyPayment(
      id: json['id'] as String? ?? '',
      status: CutluyPaymentStatus.parse(json['status'] as String?),
      statusName: json['status'] as String? ?? '',
      amount: _money(json['amount']),
      currency: json['currency'] as String? ?? 'USD',
      createdAt: created ?? DateTime.now().toUtc(),
      referenceId: json['reference_id'] as String? ?? '',
      qrString: json['qr_string'] as String? ?? '',
      checkoutUrl: json['checkout_url'] as String? ?? '',
      approvedAt: _time(json['approved_at']),
      expiresAt: expires,
    );
  }

  static double _money(Object? raw) => switch (raw) {
    final num value => value.toDouble(),
    final String value => double.tryParse(value) ?? 0,
    _ => 0,
  };

  static DateTime? _time(Object? raw) =>
      raw is String ? DateTime.tryParse(raw)?.toUtc() : null;
}

/// CutLuy answered with its documented error body:
/// `{"error": "quota_exceeded", "message": "…"}`.
class CutluyRejectException implements Exception {
  const CutluyRejectException({
    required this.httpStatus,
    required this.code,
    required this.message,
    this.retryAfter,
  });

  final int httpStatus;
  final String code;
  final String message;

  /// Set when the answer was `429 rate_limited` and said how long to wait.
  final Duration? retryAfter;

  @override
  String toString() => 'CutluyRejectException($httpStatus $code): $message';
}

/// HTTP client for the CutLuy payment API.
///
/// Two calls, both authenticated with the store's API key: ask for a QR, and
/// ask what became of a payment. There is deliberately no retry loop here —
/// creation is rate limited to 60 a minute per key and the quota is spent by
/// paid transactions, so a client that retried on its own could burn a period's
/// allowance on one confused cashier.
class CutluyClient {
  CutluyClient({
    http.Client? client,
    String? baseUrl,
    String? apiKey,
  }) : _client = client ?? http.Client(),
       _baseUrl = (baseUrl ?? AppConfig.current.cutluyBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _apiKey = apiKey ?? AppConfig.current.cutluyApiKey;

  final http.Client _client;
  final String _baseUrl;
  final String _apiKey;

  static const _paymentsPath = '/v1/payments';

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Create a payment. The reference id doubles as the idempotency key, so a
  /// retry of the same request returns the same payment instead of a second
  /// payable QR.
  Future<CutluyPayment> createPayment({
    required double amount,
    required String referenceId,
    Map<String, Object?>? metadata,
  }) async {
    final body = <String, Object?>{
      // CutLuy rejects an amount with more than two decimals (400
      // invalid_amount), and a binary total rarely lands on two: format it
      // first and send what was formatted.
      'amount': double.parse(amount.toStringAsFixed(2)),
      'reference_id': referenceId,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
      'idempotency_key': referenceId,
    };
    final json = await _send(
      'POST',
      Uri.parse('$_baseUrl$_paymentsPath'),
      body,
    );
    return _paymentOf(json, expectedId: null);
  }

  /// Read one payment back. The authenticated answer about whether money moved.
  Future<CutluyPayment> getPayment(String id) async {
    final json = await _send(
      'GET',
      Uri.parse('$_baseUrl$_paymentsPath/${Uri.encodeComponent(id)}'),
      null,
    );
    return _paymentOf(json, expectedId: id);
  }

  CutluyPayment _paymentOf(
    Map<String, dynamic> json, {
    required String? expectedId,
  }) {
    final payment = CutluyPayment.fromJson(json);
    if (payment.id.isEmpty) {
      throw const CutluyRejectException(
        httpStatus: 502,
        code: 'unreadable_answer',
        message: 'CutLuy returned a payment with no id.',
      );
    }
    if (expectedId != null && payment.id != expectedId) {
      // Reading back a different payment than was asked for would let one
      // transaction confirm another, so it is refused rather than trusted.
      throw const CutluyRejectException(
        httpStatus: 502,
        code: 'unreadable_answer',
        message: 'CutLuy answered about a different payment than was asked.',
      );
    }
    return payment;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    Uri uri,
    Map<String, Object?>? body,
  ) async {
    late final http.Response response;
    final request = http.Request(method, uri)
      ..headers.addAll({
        'authorization': 'Bearer $_apiKey',
        'content-type': 'application/json',
        'accept': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const CutluyRejectException(
        httpStatus: 504,
        code: 'timeout',
        message: 'CutLuy did not answer within 20 seconds',
      );
    } on Exception {
      throw const CutluyRejectException(
        httpStatus: 503,
        code: 'unreachable',
        message: 'CutLuy could not be reached',
      );
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      throw CutluyRejectException(
        httpStatus: response.statusCode,
        code: 'unreadable_answer',
        message:
            'CutLuy answered ${response.statusCode} with something that is '
            'not JSON',
      );
    }
    final json = Map<String, dynamic>.from(decoded);
    if (response.statusCode >= 400) throw _errorOf(response, json);
    return json;
  }

  CutluyRejectException _errorOf(
    http.Response response,
    Map<String, dynamic> json,
  ) {
    final code = json['error'] as String? ?? 'http_${response.statusCode}';
    final message = json['message'] as String? ?? '';
    final retryAfter = response.headers['retry-after'];
    return CutluyRejectException(
      httpStatus: response.statusCode,
      code: code,
      message: message.isEmpty ? code : message,
      retryAfter: int.tryParse(retryAfter ?? '') == null
          ? null
          : Duration(seconds: int.parse(retryAfter!)),
    );
  }

  void close() => _client.close();
}
