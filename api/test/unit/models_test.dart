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
  });
}
