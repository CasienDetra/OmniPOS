import 'dart:convert';

import '../config/app_config.dart';
import '../core/exceptions.dart';
import '../core/webhook_signature.dart';
import '../models/order.dart';
import 'cutluy_client.dart';
import 'payment_provider.dart';

/// The dollars a cart of shop-priced lines is worth.
///
/// Each line is converted and rounded on its own, then the lines are added up,
/// because that is the arithmetic a cashier can repeat on the screen: charging
/// the rounded sum of unrounded lines would ask the customer for money that
/// matches no figure the shop displayed. A rate of `1` returns the total
/// unchanged, which is what a shop already priced in USD wants.
double usdChargeTotal(List<OrderItem> lines, double perUsd) {
  var total = 0.0;
  for (final line in lines) {
    total += _usd(line.unitPrice * line.qty, perUsd);
  }
  // The lines are already dollars; only the sum is rounded, and rounding it
  // cannot change it by more than a cent either way.
  return _cents(total);
}

double _usd(double riel, double perUsd) => _cents(riel / perUsd);

double _cents(double dollars) => double.parse(dollars.toStringAsFixed(2));

/// CutLuy's error body translated into what the counter can do with it.
///
/// The distinction that matters is between a refusal with a reason (the cashier
/// can be told, and the attempt is recorded) and an account state the shop has
/// to fix outside the till (503, with what to fix named). A 5xx from CutLuy is
/// neither: it means CutLuy could not reach the bank, so whether the payment
/// exists is unknown and nothing is recorded.
Never cutluyFailure(CutluyRejectException failure) {
  final message = 'CutLuy: ${failure.message}';
  return switch ((failure.httpStatus, failure.code)) {
    (401, _) => throw ProviderUnavailableException(
      '$message — CUTLUY_API_KEY is not a key this store recognises.',
    ),
    (402, _) => throw ProviderUnavailableException(
      '$message — the quota for this billing period is spent. Check '
      'GET /v1/usage; a new payment is accepted once the period resets or the '
      'account is upgraded.',
    ),
    (403, _) => throw ProviderUnavailableException(
      '$message — this CutLuy account is suspended, so no payment can be '
      'created until it is settled.',
    ),
    (404, 'payment_link_not_found') ||
    (400, 'payment_link_disabled') => throw ProviderUnavailableException(
      '$message — the store behind CUTLUY_API_KEY has no usable payment link. '
      'Enable one under CutLuy Dashboard.',
    ),
    (429, _) => throw ProviderUnavailableException(
      '$message — this API key is making requests faster than CutLuy allows '
      '(60 creations, 600 reads a minute).',
      retryAfter: failure.retryAfter,
    ),
    (400, 'invalid_amount') ||
    (400, 'amount_too_low') ||
    (400, 'amount_too_high') => throw InvalidEntityException([failure.message]),
    // Includes the synthetic 503/504 this client raises when CutLuy was
    // unreachable or silent, and CutLuy's own 502 payment_provider_error.
    (>= 500, _) => throw ProviderTransportException(
      '$message (${failure.code})',
    ),
    _ => throw ProviderRejectException(failure.code, message),
  };
}

/// The ABA KHQR payments CutLuy takes, behind the same three questions every
/// provider answers.
///
/// CutLuy differs from PayWay in three ways that shape this file: it is
/// authenticated by one bearer key instead of a signed field list, it charges
/// USD only, and it signs its notifications. That last one is why
/// [readNotification] verifies before it returns anything — a notification from
/// CutLuy is evidence that CutLuy sent it, which is still not evidence that
/// money arrived, so the caller re-reads the payment either way.
class CutluyProvider implements PaymentProvider {
  CutluyProvider({AppConfig? config, CutluyClient? client})
    : _config = config ?? AppConfig.current,
      _client = client ?? CutluyClient();

  final AppConfig _config;
  final CutluyClient _client;

  @override
  String get name => 'cutluy';

  @override
  String get shopCurrency => _config.cutluyShopCurrency;

  @override
  bool get isConfigured => _config.cutluyConfigured;

  @override
  String get configurationHint {
    if (_config.cutluyApiKey.isEmpty) {
      return 'QR payments are not configured: set CUTLUY_API_KEY (CutLuy '
          'Dashboard → API keys) and, to accept webhooks, '
          'CUTLUY_WEBHOOK_SECRET.';
    }
    return 'QR payments are not configured: this shop prices in KHR and '
        'CutLuy charges USD, so set CUTLUY_KHR_USD_RATE to the riel-per-dollar '
        'rate the shop banks at.';
  }

  @override
  Future<OpenedQr> open(QrOrder order) async {
    final charge = _chargeFor(order);
    if (charge < 0.01) {
      throw InvalidEntityException([
        r'The cart is worth less than the $0.01 CutLuy charges a payment for',
      ]);
    }
    final CutluyPayment payment;
    try {
      payment = await _client.createPayment(
        amount: charge,
        referenceId: order.tranId,
        metadata: {
          // For the shop's own reports in the CutLuy dashboard. Never read back
          // as a fact: the transaction id is proved by reference_id.
          'pos_currency': order.currency,
          'pos_total': order.amount,
          'exchange_rate': _config.cutluyKhrUsdRate,
        },
      );
    } on CutluyRejectException catch (failure) {
      cutluyFailure(failure);
    }
    if (payment.qrString.isEmpty) {
      throw const ProviderRejectException(
        'no_qr',
        'CutLuy created a payment without a QR payload.',
      );
    }
    if (payment.referenceId.isNotEmpty && payment.referenceId != order.tranId) {
      throw const ProviderRejectException(
        'reference_mismatch',
        'CutLuy returned a payment for a different transaction than was '
            'requested.',
      );
    }
    return OpenedQr(
      tranId: order.tranId,
      qrString: payment.qrString,
      chargeAmount: payment.amount,
      chargeCurrency: payment.currency,
      exchangeRate: order.currency == 'USD' ? null : _config.cutluyKhrUsdRate,
      providerRef: payment.id,
      checkoutUrl: payment.checkoutUrl,
      expiresAt:
          payment.expiresAt ??
          DateTime.now().toUtc().add(_config.cutluyFallbackExpiry),
    );
  }

  @override
  Future<GatewayAnswer> lookup(String tranId, {String providerRef = ''}) async {
    if (providerRef.isEmpty) {
      // CutLuy addresses a payment by its own id, and a list filtered by
      // reference does not exist. A payment row created before this build knew
      // the id can only be expired locally.
      throw const ProviderRejectException(
        'no_provider_ref',
        'This payment was never given a CutLuy id, so the gateway cannot be '
            'asked about it.',
      );
    }
    final CutluyPayment payment;
    try {
      payment = await _client.getPayment(providerRef);
    } on CutluyRejectException catch (failure) {
      cutluyFailure(failure);
    }
    if (payment.referenceId.isNotEmpty && payment.referenceId != tranId) {
      throw const ProviderRejectException(
        'reference_mismatch',
        'CutLuy answered about a payment belonging to another transaction.',
      );
    }
    return GatewayAnswer(
      tranId: tranId,
      status: switch (payment.status) {
        CutluyPaymentStatus.paid => GatewayStatus.approved,
        CutluyPaymentStatus.scanned => GatewayStatus.scanned,
        CutluyPaymentStatus.pending => GatewayStatus.pending,
        CutluyPaymentStatus.expired => GatewayStatus.expired,
        CutluyPaymentStatus.failed => GatewayStatus.declined,
        CutluyPaymentStatus.unknown => GatewayStatus.unknown,
      },
      statusName: payment.statusName,
      providerRef: payment.id,
      chargedAmount: payment.amount,
      chargedCurrency: payment.currency,
      message: payment.status == CutluyPaymentStatus.failed
          ? 'CutLuy reported the payment as failed'
          : '',
    );
  }

  /// Never: a retried create with the same idempotency key returns the
  /// same payment, so a repeated transaction id is not a collision.
  @override
  bool isDuplicateTransaction(String code) => false;

  @override
  NotificationPointer readNotification({
    required List<int> rawBody,
    required Map<String, String> headers,
  }) {
    final secret = _config.cutluyWebhookSecret;
    if (secret.isEmpty) {
      throw const ServiceUnavailableException(
        'CutLuy notifications are not accepted: set CUTLUY_WEBHOOK_SECRET to '
        'the endpoint secret shown next to this callback URL in the CutLuy '
        'dashboard.',
      );
    }
    final header = headers['x-cutluy-signature'];
    switch (checkWebhookSignature(
      secret: secret,
      header: header,
      rawBody: rawBody,
      now: DateTime.now().toUtc(),
      tolerance: _config.cutluyWebhookTolerance,
    )) {
      case WebhookCheck.ok:
        break;
      case WebhookCheck.headerMissing:
        throw const UnauthorizedException(
          'Notification carries no X-CutLuy-Signature header',
        );
      case WebhookCheck.headerMalformed:
        throw const BadRequestException(
          'X-CutLuy-Signature is not in the "t=<unix>,v1=<hex>" form',
        );
      case WebhookCheck.timestampStale:
        throw const UnauthorizedException(
          'Notification timestamp is outside the accepted window',
        );
      case WebhookCheck.signatureMismatch:
        throw const UnauthorizedException(
          'Notification signature does not match the body',
        );
    }

    final Object? event;
    try {
      event = jsonDecode(utf8.decode(rawBody));
    } on FormatException {
      throw const BadRequestException('Notification body is not valid JSON');
    }
    final data = event is Map ? event['data'] : null;
    final payment = data is Map ? data['payment'] : null;
    if (payment is! Map) {
      throw const BadRequestException(
        'Notification carries no payment object',
      );
    }
    final reference = payment['reference_id'];
    if (reference is! String || reference.isEmpty) {
      throw const BadRequestException(
        'Notification carries no reference_id to match a payment with',
      );
    }
    // The event type and the status in the body are not read as evidence:
    // payment.completed is taken to mean "go and look", and the signed read of
    // the payment is what decides whether a Sale is written.
    return NotificationPointer(
      tranId: reference,
      providerRef: payment['id'] as String? ?? '',
    );
  }

  /// What the customer is charged, in the only currency CutLuy moves.
  double _chargeFor(QrOrder order) {
    if (order.currency == 'USD') return order.amount;
    final rate = _config.cutluyKhrUsdRate;
    if (rate <= 0) {
      throw ServiceUnavailableException(configurationHint);
    }
    // Converted from the lines, not the total, so the figure agrees with the
    // USD amounts a cashier can add up on screen.
    return usdChargeTotal(order.items, rate);
  }

  @override
  void close() => _client.close();
}
