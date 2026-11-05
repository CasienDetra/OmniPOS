import 'package:mongo_dart/mongo_dart.dart';

import '../core/pagination.dart';
import 'order.dart';

/// Where a QR payment stands, in this system's own words.
///
/// Each gateway has its own vocabulary (`APPROVED`, `scanned`, …); this is what
/// the counter displays and what the state machine allows. Only [paid] means
/// money moved, and only [paid] has a Sale.
enum PaymentStatus {
  /// Displayed, waiting for the customer to scan and confirm.
  pending,

  /// The customer's banking app has the payment open and they have not
  /// confirmed it. Nothing is sold, and the code comes off the screen: a QR a
  /// phone is holding is a QR a second customer could otherwise be shown.
  scanned,

  /// The gateway confirmed it and the Sale exists.
  paid,

  /// Nobody paid before the QR's lifetime ran out.
  expired,

  /// The payer or the gateway refused it.
  declined,

  /// The request to the gateway never produced a QR — the customer was never
  /// shown anything to scan. Terminal: the cashier starts a new payment.
  failed;

  static PaymentStatus parse(String raw) => values.firstWhere(
    (status) => status.name == raw,
    // Only this module writes the field, so an unreadable value is a bug in
    // the code, not a state to guess at.
    orElse: () => throw StateError('Unknown payment status "$raw"'),
  );

  bool get isTerminal =>
      this != PaymentStatus.pending && this != PaymentStatus.scanned;

  /// Statuses a confirmation may still be written from. A transition that
  /// filters on `pending` alone would strand a payment whose customer went on
  /// to pay after being seen to scan it: the scan is reported by the gateway,
  /// and the paid answer that follows it has to be allowed to finish the job.
  static const List<PaymentStatus> openable = [pending, scanned];
}

/// One attempt to be paid by QR.
///
/// A Payment exists before a Sale does: the cashier shows a code, and only when
/// the gateway says the code was paid does a Sale — and with it a receipt
/// number — come into being. That ordering is deliberate. Receipt numbers are
/// sequential precisely so that a gap means something, and an abandoned
/// checkout that never became a Sale leaves no gap.
class Payment {
  const Payment({
    this.id,
    required this.tranId,
    required this.cashierId,
    required this.platform,
    required this.items,
    required this.totalPrice,
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.provider = '',
    this.chargeAmount,
    this.chargeCurrency,
    this.exchangeRate,
    this.qrString = '',
    this.abapayDeeplink = '',
    this.checkoutUrl = '',
    this.appStoreUrl = '',
    this.playStoreUrl = '',
    this.gatewayPaymentId = '',
    this.gatewayTraceId = '',
    this.error,
    this.paidAt,
    this.approvalCode,
    this.paymentAmount,
    this.paymentCurrency,
    this.saleId,
    this.receiptNumber,
  });

  static Payment fromDocument(Map<String, dynamic> doc) => Payment(
    id: doc['_id'] as ObjectId?,
    tranId: doc['tran_id'] as String? ?? '',
    cashierId: doc['cashier_id'] as ObjectId?,
    platform: doc['platform'] as String? ?? 'Web',
    items: [
      for (final item in (doc['items'] as List? ?? const []))
        if (item is Map) OrderItem.fromMap(Map<String, dynamic>.from(item)),
    ],
    totalPrice: (doc['total_price'] as num?)?.toDouble() ?? 0,
    currency: doc['currency'] as String? ?? 'KHR',
    status: PaymentStatus.parse(doc['status'] as String? ?? 'pending'),
    createdAt: doc['created_at'] as DateTime? ?? DateTime.now().toUtc(),
    expiresAt: doc['expires_at'] as DateTime? ?? DateTime.now().toUtc(),
    provider: doc['provider'] as String? ?? '',
    chargeAmount: (doc['charge_amount'] as num?)?.toDouble(),
    chargeCurrency: doc['charge_currency'] as String?,
    exchangeRate: (doc['exchange_rate'] as num?)?.toDouble(),
    qrString: doc['qr_string'] as String? ?? '',
    abapayDeeplink: doc['abapay_deeplink'] as String? ?? '',
    checkoutUrl: doc['checkout_url'] as String? ?? '',
    appStoreUrl: doc['app_store_url'] as String? ?? '',
    playStoreUrl: doc['play_store_url'] as String? ?? '',
    gatewayPaymentId: doc['gateway_payment_id'] as String? ?? '',
    gatewayTraceId: doc['gateway_trace_id'] as String? ?? '',
    error: doc['error'] as String?,
    paidAt: doc['paid_at'] as DateTime?,
    approvalCode: doc['approval_code'] as String?,
    paymentAmount: (doc['payment_amount'] as num?)?.toDouble(),
    paymentCurrency: doc['payment_currency'] as String?,
    saleId: doc['sale_id'] as ObjectId?,
    receiptNumber: doc['receipt_number'] as String?,
  );

  final ObjectId? id;

  /// Our id for the gateway, at most 20 characters and unique per merchant.
  /// Everything about a payment — the QR, the notification, the poll — is
  /// addressed through it.
  final String tranId;
  final ObjectId? cashierId;

  /// Carried onto the Sale the payment produces, so a QR paid from a tablet at
  /// the table is recorded as that platform, not as `Web`.
  final String platform;

  /// The lines the customer was shown, snapshotted when the QR was made. The
  /// Sale is built from these, never from a fresh price lookup, so what was
  /// scanned is what was sold.
  final List<OrderItem> items;
  final double totalPrice;

  /// `KHR` or `USD` — the currency the shop's own prices are in, and the one
  /// the Sale is booked in.
  final String currency;

  /// Which gateway the code was asked for: `payway` or `cutluy`. A payment is
  /// settled by the provider that issued it and no other, and this says whose
  /// support desk a shop has to call.
  final String provider;

  /// What the customer is charged. Differs from [totalPrice] when the provider
  /// takes a currency the shop does not price in. Null on a payment whose
  /// provider charges the shop's own money, which needs no second figure.
  final double? chargeAmount;
  final String? chargeCurrency;

  /// Shop currency per unit of [chargeCurrency], kept on the row because the
  /// configured rate moves and a receipt has to say what it was calculated at.
  final double? exchangeRate;
  final PaymentStatus status;

  /// The EMVCo payload to render as a QR, and the links that take the customer
  /// to the payment without scanning. A gateway's branded QR image is not kept:
  /// a 0.5 MB base64 string in every row buys nothing once the code can be
  /// drawn from [qrString].
  final String qrString;
  final String abapayDeeplink;
  final String checkoutUrl;
  final String appStoreUrl;
  final String playStoreUrl;

  /// The gateway's own id for the transaction, where it issues one. CutLuy
  /// addresses a payment by this and by nothing else, so a row without it can
  /// never be asked about again.
  final String gatewayPaymentId;

  /// The gateway's trace id for the issuing call — what its support desk needs
  /// when a QR did not work.
  final String gatewayTraceId;

  /// Why the payment is `declined` or `failed`, in the gateway's words.
  final String? error;

  final DateTime createdAt;
  final DateTime expiresAt;

  final DateTime? paidAt;

  /// What the customer actually paid, which can differ from [chargeAmount] when
  /// a code in one currency is paid from an account in another.
  final double? paymentAmount;
  final String? paymentCurrency;

  /// Six-character approval code. What a customer quotes when they say the
  /// money left their account.
  final String? approvalCode;

  /// The Sale this payment created. Null until the payment is
  /// [PaymentStatus.paid].
  final ObjectId? saleId;
  final String? receiptNumber;

  /// The amount a confirmation is checked against: what the customer was asked
  /// to pay, which is the shop total unless a conversion produced the code.
  double get settledAmount => chargeAmount ?? totalPrice;

  Map<String, Object?> toDocument() => {
    'tran_id': tranId,
    'cashier_id': cashierId,
    'platform': platform,
    'items': [for (final item in items) item.toMap()],
    'total_price': totalPrice,
    'currency': currency,
    'provider': provider,
    'charge_amount': chargeAmount,
    'charge_currency': chargeCurrency,
    'exchange_rate': exchangeRate,
    'status': status.name,
    'qr_string': qrString,
    'abapay_deeplink': abapayDeeplink,
    'checkout_url': checkoutUrl,
    'app_store_url': appStoreUrl,
    'play_store_url': playStoreUrl,
    'gateway_payment_id': gatewayPaymentId,
    'gateway_trace_id': gatewayTraceId,
    'error': error,
    'created_at': createdAt.toUtc(),
    'expires_at': expiresAt.toUtc(),
    'paid_at': paidAt?.toUtc(),
    'approval_code': approvalCode,
    'payment_amount': paymentAmount,
    'payment_currency': paymentCurrency,
    'sale_id': saleId,
    'receipt_number': receiptNumber,
  };

  /// What a cashier's screen or a customer's phone needs: the code, the
  /// amount, and whether it is still worth waiting.
  ///
  /// The gateway's trace id, payment id, approval code and bank reference stay
  /// in the document. They are for support, and a POS response body is read
  /// over the shop's Wi-Fi by whoever is standing at the counter.
  Map<String, Object?> toJson({String? cashierName}) => {
    'id': idHex(id),
    'tran_id': tranId,
    'cashier_id': idHex(cashierId),
    'cashier_name': cashierName,
    'platform': platform,
    'status': status.name,
    'provider': provider,
    'amount': totalPrice,
    'currency': currency,
    'charge_amount': chargeAmount ?? totalPrice,
    'charge_currency': chargeCurrency ?? currency,
    'exchange_rate': exchangeRate,
    'items': [for (final item in items) item.toJson()],
    'qr_string': status == PaymentStatus.pending ? qrString : '',
    'abapay_deeplink': status == PaymentStatus.pending ? abapayDeeplink : '',
    'checkout_url': status == PaymentStatus.pending ? checkoutUrl : '',
    'app_store_url': appStoreUrl,
    'play_store_url': playStoreUrl,
    'created_at': createdAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'paid_at': paidAt?.toIso8601String(),
    'payment_amount': paymentAmount,
    'payment_currency': paymentCurrency,
    'error': error,
    'sale_id': idHex(saleId),
    'receipt_number': receiptNumber,
  };
}
