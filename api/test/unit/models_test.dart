import 'package:mongo_dart/mongo_dart.dart';
import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

void main() {
  group('OrderItem', () {
    test('toJson adds computed line_price', () {
      const item = OrderItem(
        productId: 'p1',
        name: 'Nasi Goreng',
        unitPrice: 15000,
        qty: 2,
      );
      expect(item.toJson()['line_price'], 30000);
    });

    test('fromMap defaults missing fields', () {
      final item = OrderItem.fromMap({});
      expect(item.productId, '');
      expect(item.name, '');
      expect(item.unitPrice, 0);
      expect(item.qty, 0);
    });
  });

  group('Order', () {
    final cashier = ObjectId();
    final order = Order(
      id: ObjectId(),
      receiptNumber: '1000002',
      cashierId: cashier,
      platform: 'Web',
      totalPrice: 30000,
      items: const [
        OrderItem(
          productId: 'p1',
          name: 'Nasi Goreng',
          unitPrice: 15000,
          qty: 2,
        ),
      ],
      orderedAt: DateTime.utc(2026, 10, 5, 7, 30),
    );

    test('document round-trip preserves all fields', () {
      final restored = Order.fromDocument({
        '_id': order.id,
        ...order.toDocument(),
      });
      expect(restored.receiptNumber, order.receiptNumber);
      expect(restored.cashierId, cashier);
      expect(restored.totalPrice, 30000);
      expect(restored.items.single.name, 'Nasi Goreng');
      expect(restored.orderedAt, DateTime.utc(2026, 10, 5, 7, 30));
    });

    test('toDocument stores items without derived line_price', () {
      final doc = order.toDocument();
      final item =
          (doc['items'] as List<Object?>).single as Map<String, Object?>;
      expect(item.containsKey('line_price'), isFalse);
      expect(item['unit_price'], 15000);
    });

    test('toJson embeds cashier name and hex ids', () {
      final json = order.toJson(cashierName: 'Cashier One');
      expect(json['id'], order.id!.oid);
      expect(json['cashier_id'], cashier.oid);
      expect(json['cashier_name'], 'Cashier One');
      expect(
        (json['items'] as List).cast<Map<String, Object?>>(),
        everyElement(containsPair('line_price', 30000)),
      );
    });

    test('fromDocument applies defaults for sparse docs', () {
      final sparse = Order.fromDocument({});
      expect(sparse.platform, 'Web');
      expect(sparse.receiptNumber, '');
      expect(sparse.items, isEmpty);
      expect(sparse.totalPrice, 0);
    });

    test('a QR sale keeps the transaction it was paid with', () {
      final qrSale = Order.fromDocument({
        ...order.toDocument(),
        'payment_tran_id': '2603121000001',
      });
      expect(qrSale.paymentTranId, '2603121000001');
      expect(qrSale.toJson()['payment_tran_id'], '2603121000001');
      expect(order.toDocument()['payment_tran_id'], isNull);
    });
  });

  group('Payment', () {
    final cashier = ObjectId();
    final created = DateTime.utc(2026, 10, 5, 7, 30);

    Payment paymentWith(PaymentStatus status) => Payment(
      tranId: '2603121000001',
      cashierId: cashier,
      platform: 'Web',
      items: const [
        OrderItem(
          productId: 'p1',
          name: 'Nasi Goreng',
          unitPrice: 15000,
          qty: 2,
        ),
      ],
      totalPrice: 30000,
      currency: 'KHR',
      status: status,
      createdAt: created,
      expiresAt: created.add(const Duration(minutes: 10)),
      qrString: '000201015123680016A00000067701011203',
      abapayDeeplink: 'ababank://payment/123',
      gatewayTraceId: 'trace-1',
      approvalCode: '544415',
    );

    /// The same payment as a KHR shop sees it when the gateway charges in USD:
    /// two money figures on one row, the shop's and the customer's.
    Payment convertedWith(PaymentStatus status) => Payment(
      tranId: '2603121000001',
      cashierId: cashier,
      platform: 'Web',
      items: paymentWith(PaymentStatus.pending).items,
      totalPrice: 15000,
      currency: 'KHR',
      status: status,
      createdAt: created,
      expiresAt: created.add(const Duration(minutes: 5)),
      provider: 'cutluy',
      chargeAmount: 3.66,
      chargeCurrency: 'USD',
      exchangeRate: 4100,
      checkoutUrl: 'https://pay.example.kh/p/PUET',
      gatewayPaymentId: 'PUETcMUOKStjZsCb6zAl8kg9fMRGM85x',
      qrString: '000201015123680016A00000067701011203',
    );

    test('document round-trip preserves what the Sale is built from', () {
      final restored = Payment.fromDocument({
        '_id': ObjectId(),
        ...paymentWith(PaymentStatus.pending).toDocument(),
      });
      expect(restored.tranId, '2603121000001');
      expect(restored.cashierId, cashier);
      expect(restored.totalPrice, 30000);
      expect(restored.currency, 'KHR');
      expect(restored.status, PaymentStatus.pending);
      expect(restored.items.single.name, 'Nasi Goreng');
      expect(restored.expiresAt, created.add(const Duration(minutes: 10)));
    });

    test('the code disappears once the payment is no longer payable', () {
      expect(
        paymentWith(PaymentStatus.pending).toJson()['qr_string'],
        isNotEmpty,
      );
      for (final status in PaymentStatus.values.where((s) => s.isTerminal)) {
        final json = paymentWith(status).toJson();
        expect(json['qr_string'], '', reason: status.name);
        expect(json['abapay_deeplink'], '', reason: status.name);
      }
    });

    test(
      'a scanned code is taken off the screen but the payment stays open',
      () {
        // Someone's banking app is holding this payment. Nothing is sold, and a
        // second customer must not be shown the same code, but the row is still
        // one a confirmation can be written for.
        final json = paymentWith(PaymentStatus.scanned).toJson();
        expect(json['qr_string'], '');
        expect(json['abapay_deeplink'], '');
        expect(json['status'], 'scanned');
        expect(PaymentStatus.scanned.isTerminal, isFalse);
        expect(PaymentStatus.openable, [
          PaymentStatus.pending,
          PaymentStatus.scanned,
        ]);
        expect(
          PaymentStatus.values.where((s) => !s.isTerminal).toSet(),
          PaymentStatus.openable.toSet(),
        );
      },
    );

    test('only paid is money', () {
      for (final status in PaymentStatus.values) {
        expect(
          status == PaymentStatus.paid,
          status.name == 'paid',
          reason: status.name,
        );
      }
      expect(PaymentStatus.values.map((s) => s.name).toSet(), {
        'pending',
        'scanned',
        'paid',
        'expired',
        'declined',
        'failed',
      });
    });

    test('what the gateway charged and converted survives the round trip', () {
      final restored = Payment.fromDocument({
        '_id': ObjectId(),
        ...convertedWith(PaymentStatus.pending).toDocument(),
      });
      expect(restored.provider, 'cutluy');
      expect(restored.chargeAmount, 3.66);
      expect(restored.chargeCurrency, 'USD');
      expect(restored.exchangeRate, 4100);
      expect(restored.gatewayPaymentId, 'PUETcMUOKStjZsCb6zAl8kg9fMRGM85x');
      // The shop's own money is untouched: the Sale is booked from the KHR
      // lines, not from what the customer was charged in dollars.
      expect(restored.totalPrice, 15000);
      expect(restored.currency, 'KHR');
      final json = restored.toJson();
      expect(json['amount'], 15000);
      expect(json['charge_amount'], 3.66);
      expect(json['exchange_rate'], 4100);
      expect(json['checkout_url'], 'https://pay.example.kh/p/PUET');
    });

    test('a payment that was never converted has no rate to report', () {
      final payway = paymentWith(PaymentStatus.pending);
      expect(payway.chargeAmount, isNull);
      expect(payway.exchangeRate, isNull);
      expect(payway.settledAmount, 30000);
      expect(payway.toJson()['charge_amount'], 30000);
      expect(payway.toJson()['charge_currency'], 'KHR');
      expect(payway.toJson()['exchange_rate'], isNull);
    });

    test('a confirmation is checked against what the customer was charged', () {
      // Comparing a dollar answer with the riel total on the row would refuse
      // every converted payment, so the figure compared against is the charge.
      expect(convertedWith(PaymentStatus.pending).settledAmount, 3.66);
    });

    test('the hosted checkout link goes with the code and no further', () {
      // A checkout page is as live as the QR it mirrors: once the payment is
      // not payable, the link must not stay on the response either.
      expect(
        convertedWith(PaymentStatus.pending).toJson()['checkout_url'],
        'https://pay.example.kh/p/PUET',
      );
      for (final status in PaymentStatus.values.where((s) => s.isTerminal)) {
        expect(
          convertedWith(status).toJson()['checkout_url'],
          '',
          reason: status.name,
        );
      }
      expect(
        convertedWith(PaymentStatus.scanned).toJson()['checkout_url'],
        '',
      );
    });

    test('support references stay out of the response body', () {
      final json = paymentWith(PaymentStatus.paid).toJson();
      expect(json.containsKey('gateway_trace_id'), isFalse);
      expect(json.containsKey('gateway_payment_id'), isFalse);
      expect(json.containsKey('approval_code'), isFalse);
      expect(json['receipt_number'], isNull);
    });

    test('fromDocument reads a status the database wrote, and only those', () {
      expect(
        () => Payment.fromDocument({'status': 'shipped'}),
        throwsStateError,
      );
      expect(
        Payment.fromDocument({}).status,
        PaymentStatus.pending,
        reason: 'a row without a status was never confirmed',
      );
    });
  });
}
