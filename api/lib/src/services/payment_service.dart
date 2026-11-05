import 'package:mongo_dart/mongo_dart.dart';

import '../config/app_config.dart';
import '../core/exceptions.dart';
import '../models/order.dart';
import '../models/payment.dart';
import '../repositories/mongo.dart';
import 'counter_service.dart';
import 'order_service.dart';
import 'payment_provider.dart';

/// Payment by QR, from the counter's point of view.
///
/// The whole module is one state machine over [Payment.status], and two rules
/// hold it together. Nothing is paid until the provider says so — a payment
/// notification is only a hint to go and ask, because a gateway's notification
/// is not the money arriving. And a Sale is created exactly once per
/// transaction id, by the unique index on `orders.payment_tran_id`, not by a
/// check that two concurrent confirmations could both pass.
///
/// Which gateway is behind this is configuration. [PaymentProvider] is the seam
/// and `PAYMENT_PROVIDER` picks the implementation, so a shop moves between
/// CutLuy and PayWay without a code change and the routes never learn the
/// difference.
class PaymentService {
  PaymentService({
    OrderService? orders,
    CounterService? counters,
    PaymentProvider? gateway,
    AppConfig? config,
  }) : _orders = orders ?? OrderService(),
       _counters = counters ?? CounterService(),
       _gateway =
           gateway ?? defaultPaymentProvider(config ?? AppConfig.current);

  final OrderService _orders;
  final CounterService _counters;
  final PaymentProvider _gateway;

  static const _collection = 'payments';

  /// Show a cashier a QR for a cart.
  ///
  /// The cart is priced here and the priced lines are stored on the Payment,
  /// so the Sale that a successful payment produces is built from the same
  /// snapshot the customer was shown — not from whatever the catalogue says by
  /// then.
  Future<Payment> createPayment({
    required String cart,
    required String platform,
    required ObjectId cashierId,
  }) async {
    _requireConfigured();
    final priced = await _orders.priceCart(cart);
    final currency = _gateway.shopCurrency;

    try {
      return await _openAndSave(
        priced: priced,
        currency: currency,
        platform: platform,
        cashierId: cashierId,
      );
    } on ProviderRejectException catch (exception) {
      // The attempt is recorded even though the customer was never shown a
      // code: a cashier who says "the terminal refused me" needs the reason the
      // gateway gave, and it is not recoverable from anywhere else.
      //
      // A transport failure deliberately records nothing. Whether the gateway
      // holds a live QR for that transaction id is unknown, and a `failed` row
      // would invite a second attempt that puts two payable codes on the same
      // counter. The orphan expires on the lifetime it was given.
      await _saveFailedAttempt(
        priced: priced,
        currency: currency,
        platform: platform,
        cashierId: cashierId,
        error: exception.message,
      );
      throw BadGatewayException(exception.message);
    } on ProviderTransportException catch (exception) {
      throw BadGatewayException(exception.message);
    } on ProviderUnavailableException catch (exception) {
      throw ServiceUnavailableException(_unavailableMessage(exception));
    }
  }

  Future<Payment> _openAndSave({
    required PricedCart priced,
    required String currency,
    required String platform,
    required ObjectId cashierId,
  }) async {
    // One retry: a re-seeded database can hand out a transaction id the gateway
    // already associates with something else, and only the gateway knows.
    for (var attempt = 0; attempt < 2; attempt++) {
      final tranId = await _counters.nextPaymentTranId();
      final OpenedQr qr;
      try {
        qr = await _gateway.open(
          QrOrder(
            tranId: tranId,
            items: priced.items,
            amount: priced.totalPrice,
            currency: currency,
          ),
        );
      } on ProviderRejectException catch (exception) {
        if (!_gateway.isDuplicateTransaction(exception.code)) rethrow;
        continue;
      }

      final now = DateTime.now().toUtc();
      final payment = Payment(
        tranId: qr.tranId,
        cashierId: cashierId,
        platform: platform.isEmpty ? 'Web' : platform,
        items: priced.items,
        totalPrice: priced.totalPrice,
        currency: currency,
        status: PaymentStatus.pending,
        createdAt: now,
        expiresAt: qr.expiresAt,
        provider: _gateway.name,
        // Recorded only when the gateway charged a currency other than the
        // shop's: a receipt wants one money figure normally and two when a
        // conversion stood between the shelf and the bank.
        chargeAmount: qr.exchangeRate == null ? null : qr.chargeAmount,
        chargeCurrency: qr.exchangeRate == null ? null : qr.chargeCurrency,
        exchangeRate: qr.exchangeRate,
        qrString: qr.qrString,
        abapayDeeplink: qr.payUrl,
        checkoutUrl: qr.checkoutUrl,
        appStoreUrl: qr.appStoreUrl,
        playStoreUrl: qr.playStoreUrl,
        gatewayPaymentId: qr.providerRef,
        gatewayTraceId: qr.traceId,
      );
      await insertDoc(_collection, payment.toDocument());
      return payment;
    }
    throw BadGatewayException(
      '${_gateway.name} rejected every transaction id this terminal offered. '
      'It has likely been re-seeded; contact support with the merchant or '
      'store id.',
    );
  }

  Future<void> _saveFailedAttempt({
    required PricedCart priced,
    required String currency,
    required String platform,
    required ObjectId cashierId,
    required String error,
  }) async {
    final now = DateTime.now().toUtc();
    await insertDoc(
      _collection,
      Payment(
        tranId: 'failed-${now.microsecondsSinceEpoch}',
        cashierId: cashierId,
        platform: platform.isEmpty ? 'Web' : platform,
        items: priced.items,
        totalPrice: priced.totalPrice,
        currency: currency,
        provider: _gateway.name,
        status: PaymentStatus.failed,
        createdAt: now,
        expiresAt: now,
        error: error,
      ).toDocument(),
    );
  }

  /// The payment as it stands now, asking the gateway if it is still open.
  ///
  /// This is the read a cashier's screen polls, and the work a notification
  /// triggers. A payment left `pending` is not a fact about the customer's
  /// phone — the notification may never have arrived, so the poll is what
  /// actually closes a sale. Pass [cashier] to confine the read to the terminal
  /// that opened it.
  Future<Payment> refresh(String tranId, {ObjectId? cashier}) async {
    final payment = await get(tranId);
    if (cashier != null && payment.cashierId != cashier) {
      throw const ForbiddenException('This payment belongs to another cashier');
    }
    // A payment the gateway has only seen scanned is still open: the customer
    // may confirm it a moment later, and the poll is what finishes the job.
    if (!PaymentStatus.openable.contains(payment.status)) return payment;
    _requireConfigured();

    final GatewayAnswer answer;
    try {
      answer = await _gateway.lookup(
        tranId,
        providerRef: payment.gatewayPaymentId,
      );
    } on ProviderRejectException {
      // The gateway has no record of it: either it is older than what it keeps
      // answerable, or the id never reached it. Nothing about the money is
      // known, so the stored state stands and the caller can try again — except
      // past expiry, where waiting is no longer possible.
      if (_isExpired(payment, DateTime.now().toUtc())) {
        return _expire(payment);
      }
      return payment;
    } on ProviderUnavailableException catch (exception) {
      throw ServiceUnavailableException(_unavailableMessage(exception));
    }
    return switch (answer.status) {
      GatewayStatus.approved => await _confirm(payment, answer),
      GatewayStatus.scanned => await _markScanned(payment),
      GatewayStatus.pending => await _settleOrWait(payment),
      GatewayStatus.declined => await _markTerminal(
        payment,
        PaymentStatus.declined,
        '${_gateway.name}: ${answer.statusName}',
      ),
      GatewayStatus.expired => await _markTerminal(
        payment,
        PaymentStatus.expired,
        'The transaction was closed at ${_gateway.name} before it was paid',
      ),
      GatewayStatus.unknown => await _settleOrWait(payment),
    };
  }

  /// Where a delivery points, once its provider has vouched for it.
  ///
  /// The provider decides what vouching means. CutLuy signs its notifications,
  /// so an unverifiable delivery is refused here and never reaches the state
  /// machine. PayWay signs nothing, so this hands back a transaction id that is
  /// worth a lookup and nothing more — which is exactly what a
  /// [refresh] treats it as.
  NotificationPointer readNotification({
    required List<int> rawBody,
    required Map<String, String> headers,
  }) {
    _requireConfigured();
    return _gateway.readNotification(rawBody: rawBody, headers: headers);
  }

  Future<Payment> get(String tranId) async {
    final payment = await find(tranId);
    if (payment == null) throw NotFoundException('Payment "$tranId" not found');
    return payment;
  }

  Future<Payment?> find(String tranId) async {
    final doc = await findDoc(_collection, {'tran_id': tranId});
    return doc == null ? null : Payment.fromDocument(doc);
  }

  /// Turn a confirmed gateway answer into a Sale, once.
  ///
  /// The Sale is written first and the payment marked after, because the two
  /// orders fail differently. Mark the payment paid and crash before the Sale
  /// exists and the money is taken with no receipt — unrecoverable. Write the
  /// Sale and crash before the payment is marked, and the next confirmation
  /// (a retry from the gateway, the cashier's next poll) finds the Sale already
  /// there by its transaction id, marks the payment, and the shop loses
  /// nothing.
  Future<Payment> _confirm(
    Payment payment,
    GatewayAnswer answer,
  ) async {
    _requireAmountMatches(payment, answer);

    final sale = await _saleForPayment(payment);

    await updateWhere(
      _collection,
      {
        'tran_id': payment.tranId,
        'status': {r'$in': _openableNames},
      },
      {
        'status': PaymentStatus.paid.name,
        'sale_id': sale.id,
        'receipt_number': sale.receiptNumber,
        'paid_at': DateTime.now().toUtc(),
        'approval_code': answer.approvalCode,
        'payment_amount': answer.paidAmount,
        'payment_currency': answer.paidCurrency,
        'error': null,
      },
    );
    // Whoever lost the race re-reads the row: the same answer either way, and
    // nobody gets to believe they created a second Sale.
    return get(payment.tranId);
  }

  /// The Sale for this payment, creating it if this is the first confirmation.
  ///
  /// A duplicate-key failure is not an error here, it is the unique index doing
  /// its job — some other confirmation won — so the existing Sale is read back
  /// and used.
  Future<Order> _saleForPayment(Payment payment) async {
    final existing = await findDoc('orders', {
      'payment_tran_id': payment.tranId,
    });
    if (existing != null) return Order.fromDocument(existing);

    try {
      return await _orders.createSale(
        items: payment.items,
        totalPrice: payment.totalPrice,
        cashierId: payment.cashierId!,
        platform: payment.platform,
        paymentTranId: payment.tranId,
        // The customer has already paid. Refusing the Sale over stock would
        // take the money and leave no receipt, so the shelf is allowed to go
        // negative and the low-stock report surfaces it.
        enforceStock: false,
      );
    } on MongoDartError catch (error) {
      if (!_isDuplicateKey(error)) rethrow;
      final raced = await findDoc('orders', {
        'payment_tran_id': payment.tranId,
      });
      if (raced == null) rethrow;
      return Order.fromDocument(raced);
    }
  }

  /// Records that the customer's app is holding the payment. Not money.
  Future<Payment> _markScanned(Payment payment) async {
    await updateWhere(
      _collection,
      {'tran_id': payment.tranId, 'status': PaymentStatus.pending.name},
      {'status': PaymentStatus.scanned.name},
    );
    return get(payment.tranId);
  }

  Future<Payment> _markTerminal(
    Payment payment,
    PaymentStatus status,
    String error,
  ) async {
    await updateWhere(
      _collection,
      {
        'tran_id': payment.tranId,
        'status': {r'$in': _openableNames},
      },
      {'status': status.name, 'error': error},
    );
    return get(payment.tranId);
  }

  Future<Payment> _expire(Payment payment) => _markTerminal(
    payment,
    PaymentStatus.expired,
    'Nobody paid before the QR expired',
  );

  /// Wait on a payment the gateway has not settled, unless the wait is over.
  Future<Payment> _settleOrWait(Payment payment) async =>
      _isExpired(payment, DateTime.now().toUtc())
      ? await _expire(payment)
      : payment;

  /// Money for a different amount is not this payment, whatever the gateway
  /// says about the transaction id.
  void _requireAmountMatches(Payment payment, GatewayAnswer answer) {
    final settled = answer.chargedAmount;
    if (settled != null && (settled - payment.settledAmount).abs() > 0.001) {
      throw ConflictException(
        '${_gateway.name} confirmed ${answer.chargedAmount} '
        '${answer.chargedCurrency ?? payment.chargeCurrency ?? 'the same'} '
        'for transaction ${payment.tranId}, which was issued for '
        '${payment.settledAmount}. The sale was not recorded; contact the '
        'gateway with the transaction id.',
      );
    }
  }

  static List<String> get _openableNames => [
    for (final status in PaymentStatus.openable) status.name,
  ];

  static bool _isExpired(Payment payment, DateTime now) =>
      now.isAfter(payment.expiresAt);

  static bool _isDuplicateKey(MongoDartError error) =>
      error.mongoCode == 11000 ||
      error.errorCodeName == 'DuplicateKey' ||
      error.message.contains('E11000');

  /// A provider that will not transact is passed through as it was learned:
  /// how long to keep the cashier waiting is part of what it said.
  static String _unavailableMessage(ProviderUnavailableException exception) {
    final retry = exception.retryAfter;
    if (retry == null) return exception.message;
    final seconds = retry.inSeconds;
    final wait = seconds < 60
        ? '$seconds seconds'
        : '${(seconds / 60).ceil()} minutes';
    return '${exception.message} Try again in $wait.';
  }

  void _requireConfigured() {
    if (!_gateway.isConfigured) {
      throw ServiceUnavailableException(_gateway.configurationHint);
    }
  }
}
