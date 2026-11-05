import 'dart:convert';

import '../config/app_config.dart';
import '../core/exceptions.dart';
import 'payment_provider.dart';
import 'payway_client.dart';

/// ABA PayWay, behind the same three questions every provider answers.
///
/// PayWay's shape differs from CutLuy's in the ways that matter here: every
/// request carries its own signature built from a field list, it will take KHR
/// as well as USD so no conversion happens, it addresses a transaction by the
/// id the merchant invented, and its payment notification carries no signature
/// at all — which is why [readNotification] returns a pointer and nothing more.
class PaywayProvider implements PaymentProvider {
  PaywayProvider({AppConfig? config, PaywayClient? client})
    : _config = config ?? AppConfig.current,
      _client = client ?? PaywayClient();

  final AppConfig _config;
  final PaywayClient _client;

  @override
  String get name => 'payway';

  @override
  String get shopCurrency => _config.paywayCurrency;

  @override
  bool get isConfigured => _config.paywayConfigured;

  @override
  String get configurationHint =>
      'QR payments are not configured: set PAYWAY_MERCHANT_ID and '
      'PAYWAY_API_KEY. Sandbox keys come from '
      'https://sandbox.payway.com.kh/register-sandbox/';

  @override
  Future<OpenedQr> open(QrOrder order) async {
    _requirePayable(order.amount, order.currency);
    final request = PaywayQrRequest(
      tranId: order.tranId,
      amount: order.amount,
      currency: order.currency,
      lifetime: _config.paywayQrLifetime,
      callbackUrl: _config.paywayCallbackUrl.isEmpty
          ? null
          : _config.paywayCallbackUrl,
      items: encodedItemsRemark(order.items),
      // The transaction id, echoed back on the notification. It is not trusted
      // as an identifier on its own; it is what lets a callback find the row it
      // belongs to, and the gateway is asked again from there.
      returnParams: jsonEncode({'tran_id': order.tranId}),
      qrImageTemplate: _config.paywayQrImageTemplate.isEmpty
          ? null
          : _config.paywayQrImageTemplate,
    );

    final PaywayQr qr;
    try {
      qr = await _client.generateQr(request);
    } on PaywayRejectException catch (exception) {
      throw ProviderRejectException(exception.code, exception.message);
    } on PaywayTransportException catch (exception) {
      throw ProviderTransportException(exception.message);
    }
    return OpenedQr(
      tranId: order.tranId,
      qrString: qr.qrString,
      chargeAmount: order.amount,
      chargeCurrency: order.currency,
      payUrl: qr.abapayDeeplink,
      appStoreUrl: qr.appStoreUrl,
      playStoreUrl: qr.playStoreUrl,
      traceId: qr.traceId,
      expiresAt: DateTime.now().toUtc().add(_config.paywayQrLifetime),
    );
  }

  @override
  Future<GatewayAnswer> lookup(String tranId, {String providerRef = ''}) async {
    // PayWay has no id of its own for a transaction: the merchant's number is
    // the address, so [providerRef] is ignored.
    final PaywayTransactionCheck check;
    try {
      check = await _client.checkTransaction(tranId);
    } on PaywayRejectException catch (exception) {
      throw ProviderRejectException(exception.code, exception.message);
    } on PaywayTransportException catch (exception) {
      throw ProviderTransportException(exception.message);
    }
    return GatewayAnswer(
      tranId: tranId,
      status: switch (check.status) {
        PaywayTransactionStatus.approved => GatewayStatus.approved,
        PaywayTransactionStatus.pending => GatewayStatus.pending,
        PaywayTransactionStatus.declined => GatewayStatus.declined,
        PaywayTransactionStatus.cancelled => GatewayStatus.expired,
        // A hold or a refund is not a completed sale at the counter, and
        // anything unrecognised is not evidence either.
        _ => GatewayStatus.unknown,
      },
      statusName: check.paymentStatusName,
      chargedAmount: check.totalAmount,
      paidAmount: check.paymentAmount,
      paidCurrency: check.paymentCurrency,
      approvalCode: check.approvalCode,
    );
  }

  @override
  NotificationPointer readNotification({
    required List<int> rawBody,
    required Map<String, String> headers,
  }) {
    final fields = _fields(rawBody, headers);
    final tranId = fields['tran_id'];
    if (tranId is! String || tranId.isEmpty) {
      throw const BadRequestException('Notification carries no tran_id');
    }
    // Nothing here is signed, so nothing here is believed. The caller holds a
    // transaction id and goes and asks the gateway what it says about it.
    return NotificationPointer(tranId: tranId);
  }

  /// A notification arrives either as a JSON object or as a form post,
  /// depending on how the merchant profile was filled in. Both are read;
  /// neither is trusted.
  static Map<String, Object?> _fields(
    List<int> rawBody,
    Map<String, String> headers,
  ) {
    final text = utf8.decode(rawBody, allowMalformed: true);
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return Uri.splitQueryString(text);
    }
    if (decoded is Map) return decoded.cast<String, Object?>();
    return const {};
  }

  /// Riel cannot carry decimals at the gateway (code `46`) and a payment
  /// below 100 riel is refused (code `47`); USD starts at one cent. Checked
  /// before the request because the alternative is a cashier watching a
  /// spinner while the call fails a round trip to the bank.
  static void _requirePayable(double amount, String currency) {
    if (currency == 'KHR') {
      if (amount != amount.roundToDouble()) {
        throw InvalidEntityException([
          'KHR payments must be whole riel, and the cart totals $amount',
        ]);
      }
      if (amount < 100) {
        throw InvalidEntityException(['KHR payments start at 100 riel']);
      }
      return;
    }
    if (amount < 0.01) {
      throw InvalidEntityException(['USD payments start at 0.01']);
    }
  }

  @override
  bool isDuplicateTransaction(String code) =>
      code == paywayDuplicateTranId || code == '403';

  @override
  void close() => _client.close();
}
