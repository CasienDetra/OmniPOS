import 'dart:convert';

import '../config/app_config.dart';
import '../core/exceptions.dart';
import '../models/order.dart';
import 'cutluy_provider.dart';
import 'payway_provider.dart';

/// The payment providers this build can take money through. The value of
/// `PAYMENT_PROVIDER` must be one of these; the same payment routes serve
/// whichever one is selected.
const List<String> paymentProviderNames = ['payway', 'cutluy'];

/// What a gateway says about a transaction, in this system's own words.
///
/// Each provider has its own vocabulary; this is the small set the counter's
/// state machine understands. Only [approved] means money moved, and the
/// gateway's own answer — never a notification's claim — is what puts it here.
enum GatewayStatus {
  /// Paid. The only status that produces a Sale.
  approved,

  /// The customer has the payment open in their banking app and has not
  /// confirmed it. Waiting room, not money.
  scanned,

  /// Still waiting for a customer to scan.
  pending,

  /// Refused by the payer or the gateway.
  declined,

  /// Closed before anyone paid.
  expired,

  /// Anything the provider could not map, including a gateway it has never
  /// seen answer before.
  unknown,
}

/// What the counter is asking a gateway to make payable.
class QrOrder {
  const QrOrder({
    required this.tranId,
    required this.items,
    required this.amount,
    required this.currency,
  });

  /// This POS's id for the transaction. Providers use it as their own
  /// reference and as the key that makes a retried request safe.
  final String tranId;

  /// The priced lines, for a provider that wants to describe the sale to its
  /// reports.
  final List<OrderItem> items;

  /// The total in the shop's own currency — what the receipt will say.
  final double amount;
  final String currency;
}

/// A QR a gateway agreed to issue.
class OpenedQr {
  const OpenedQr({
    required this.tranId,
    required this.qrString,
    required this.chargeAmount,
    required this.chargeCurrency,
    required this.expiresAt,
    this.exchangeRate,
    this.providerRef = '',
    this.payUrl = '',
    this.checkoutUrl = '',
    this.appStoreUrl = '',
    this.playStoreUrl = '',
    this.traceId = '',
  });

  final String tranId;

  /// The EMVCo payload to draw as a QR. Rendering this locally beats taking a
  /// gateway's base64 PNG: smaller, and it cannot go stale on a cached screen.
  final String qrString;

  /// The gateway's own id for the transaction, when it has one distinct from
  /// [tranId]. What a notification and a later lookup are addressed with.
  final String providerRef;

  /// What the customer pays, which is [QrOrder.amount] unless the provider
  /// charges in a different currency and converts.
  final double chargeAmount;
  final String chargeCurrency;

  /// Shop currency per unit of [chargeCurrency], when a conversion produced
  /// this code. Null when there was none: a receipt has to say what rate was
  /// applied, because the configured rate moves and this figure may be argued
  /// about months later.
  final double? exchangeRate;

  /// When the code stops being payable. The gateway's word, because the
  /// cashier's countdown and the expiry that ends a Sale attempt both have to
  /// agree with what the bank will honour.
  final DateTime expiresAt;

  /// A link that opens the payer's app directly, instead of scanning.
  final String payUrl;

  /// A hosted checkout page the customer can be sent to instead.
  final String checkoutUrl;
  final String appStoreUrl;
  final String playStoreUrl;

  /// The gateway's trace id for this request — what its support desk needs.
  final String traceId;
}

/// A gateway's answer about one transaction.
class GatewayAnswer {
  const GatewayAnswer({
    required this.tranId,
    required this.status,
    required this.statusName,
    this.providerRef = '',
    this.chargedAmount,
    this.chargedCurrency,
    this.paidAmount,
    this.paidCurrency,
    this.approvalCode,
    this.message = '',
  });

  final String tranId;
  final GatewayStatus status;

  /// The gateway's own wording, kept for the audit trail.
  final String statusName;
  final String providerRef;

  /// The amount the transaction was created for. Compared against what this
  /// service recorded before a Sale is written.
  final double? chargedAmount;
  final String? chargedCurrency;

  /// What actually arrived, which can differ from [chargedAmount] when a code
  /// in one currency is paid from an account in another.
  final double? paidAmount;
  final String? paidCurrency;

  final String? approvalCode;

  /// Anything the gateway said worth showing a cashier when the answer is not
  /// `approved`.
  final String message;
}

/// Where a gateway's notification points.
///
/// A pointer, not a decision: it names the transaction to go and look up. What
/// a provider can prove about the delivery is its own business — see
/// [PaymentProvider.readNotification].
class NotificationPointer {
  const NotificationPointer({required this.tranId, this.providerRef = ''});

  final String tranId;
  final String providerRef;
}

/// The provider refused to do what was asked, and said why.
class ProviderRejectException implements Exception {
  const ProviderRejectException(this.code, this.message);

  /// The gateway's code as a string, for providers that have codes at all.
  final String code;
  final String message;

  @override
  String toString() => 'ProviderRejectException($code): $message';
}

/// The provider could not be reached, or answered something unreadable.
/// Nothing about the transaction is known, which is why a caller must not
/// record a failure of this kind as a dead payment.
class ProviderTransportException implements Exception {
  const ProviderTransportException(this.message);

  final String message;

  @override
  String toString() => 'ProviderTransportException: $message';
}

/// The provider will not take money right now for a reason the counter cannot
/// fix: the key is wrong, the account is suspended, the period's quota is spent
/// or the caller is being rate limited. Always a 503 to the client.
class ProviderUnavailableException implements Exception {
  const ProviderUnavailableException(this.message, {this.retryAfter});

  final String message;

  /// How long the provider asked to be left alone, when it said.
  final Duration? retryAfter;

  @override
  String toString() => 'ProviderUnavailableException: $message';
}

/// A payment gateway, from the point of view of the counter.
///
/// Three questions only: make this payable, what became of it, and what does
/// this delivery refer to. Everything a provider knows about hashes, bearer
/// tokens, currency conversion and its own error codes stays behind this seam,
/// because the state machine that turns money into receipts must not have to
/// care which bank it is talking to.
abstract class PaymentProvider {
  /// The value `PAYMENT_PROVIDER` takes to select this provider.
  String get name;

  /// The currency the shop's own prices are in, as this provider understands
  /// it. A provider that charges in something else converts.
  String get shopCurrency;

  /// Whether the credentials this provider needs are present. A deployment
  /// without them still starts; its payment routes answer 503.
  bool get isConfigured;

  /// What to set to get [isConfigured], in one sentence.
  String get configurationHint;

  /// Ask for a code to show a customer. Throws [ProviderRejectException] if the
  /// gateway refused, [ProviderUnavailableException] if it will not transact,
  /// and [ProviderTransportException] if it could not be reached at all.
  Future<OpenedQr> open(QrOrder order);

  /// Ask what became of a transaction. This is the only read that may complete
  /// a Sale, and it is authenticated by this service's own credentials.
  ///
  /// [providerRef] is the gateway's own id for the transaction, as it was
  /// returned when the QR was issued. Providers that address a payment by it
  /// and by nothing else will refuse a lookup without it.
  Future<GatewayAnswer> lookup(String tranId, {String providerRef = ''});

  /// Read a delivery and say which transaction it refers to.
  ///
  /// A provider that signs its notifications must verify before returning
  /// anything, and say so with an [AppException] when it cannot: a POS has no
  /// way to tell one provider's evidence from another's. A provider that signs
  /// nothing returns a pointer that is worth exactly nothing on its own, which
  /// is why the caller re-reads [lookup] either way.
  NotificationPointer readNotification({
    required List<int> rawBody,
    required Map<String, String> headers,
  });

  /// Whether a rejection code from [open] means "this transaction id is already
  /// known to you, offer another one".
  bool isDuplicateTransaction(String code) => false;

  void close() {}
}

/// Base64 of the line list, for a gateway that treats it as a remark and
/// ignores the numbers in it.
///
/// Returns null rather than a truncated list: the remark is decoration on the
/// provider's reports, and cutting a receipt short is worse than sending none.
String? encodedItemsRemark(List<OrderItem> items, {int maxLength = 500}) {
  if (items.isEmpty) return null;
  final encoded = base64Encode(
    utf8.encode(
      jsonEncode([
        for (final item in items)
          {'name': item.name, 'quantity': item.qty, 'price': item.unitPrice},
      ]),
    ),
  );
  return encoded.length > maxLength ? null : encoded;
}

/// The provider `PAYMENT_PROVIDER` asks for.
PaymentProvider defaultPaymentProvider(AppConfig config) {
  return switch (config.paymentProvider.toLowerCase()) {
    'cutluy' => CutluyProvider(config: config),
    'payway' => PaywayProvider(config: config),
    final other => MisconfiguredProvider(other),
  };
}

/// Stands in for a `PAYMENT_PROVIDER` that names no gateway.
///
/// A typo there must not be read as a request for either provider, and must not
/// stop the rest of the POS from working. Every payment it is asked about
/// answers 503 with the name that was written.
class MisconfiguredProvider implements PaymentProvider {
  const MisconfiguredProvider(this.name);

  @override
  final String name;

  @override
  String get shopCurrency => '';

  @override
  bool get isConfigured => false;

  @override
  String get configurationHint =>
      'PAYMENT_PROVIDER is "$name", which is not a payment provider. '
      'Set it to one of ${paymentProviderNames.join(' or ')}.';

  Never _refuse() => throw ServiceUnavailableException(configurationHint);

  @override
  Future<OpenedQr> open(QrOrder order) => _refuse();

  @override
  Future<GatewayAnswer> lookup(String tranId, {String providerRef = ''}) =>
      _refuse();

  @override
  NotificationPointer readNotification({
    required List<int> rawBody,
    required Map<String, String> headers,
  }) => _refuse();

  @override
  bool isDuplicateTransaction(String code) => false;

  @override
  void close() {}
}
