import 'package:mongo_dart/mongo_dart.dart';

import '../core/pagination.dart';

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.qty,
  });

  static OrderItem fromMap(Map<String, dynamic> map) => OrderItem(
    productId: map['product_id'] as String? ?? '',
    name: map['name'] as String? ?? '',
    unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
    qty: (map['qty'] as num?)?.toInt() ?? 0,
  );

  final String productId;
  final String name;
  final double unitPrice;
  final int qty;

  Map<String, Object?> toMap() => {
    'product_id': productId,
    'name': name,
    'unit_price': unitPrice,
    'qty': qty,
  };

  Map<String, Object?> toJson() => {
    'product_id': productId,
    'name': name,
    'unit_price': unitPrice,
    'qty': qty,
    'line_price': unitPrice * qty,
  };
}

class Order {
  const Order({
    this.id,
    required this.receiptNumber,
    required this.cashierId,
    required this.platform,
    required this.totalPrice,
    required this.items,
    required this.orderedAt,
  });

  static Order fromDocument(Map<String, dynamic> doc) => Order(
    id: doc['_id'] as ObjectId?,
    receiptNumber: doc['receipt_number'] as String? ?? '',
    cashierId: doc['cashier_id'] as ObjectId?,
    platform: doc['platform'] as String? ?? 'Web',
    totalPrice: (doc['total_price'] as num?)?.toDouble() ?? 0,
    items: [
      for (final item in (doc['items'] as List? ?? const []))
        if (item is Map) OrderItem.fromMap(Map<String, dynamic>.from(item)),
    ],
    orderedAt: doc['ordered_at'] as DateTime? ?? DateTime.now(),
  );

  final ObjectId? id;
  final String receiptNumber;
  final ObjectId? cashierId;
  final String platform;
  final double totalPrice;
  final List<OrderItem> items;
  final DateTime orderedAt;

  Map<String, Object?> toDocument() => {
    'receipt_number': receiptNumber,
    'cashier_id': cashierId,
    'platform': platform,
    'total_price': totalPrice,
    'items': [for (final item in items) item.toMap()],
    'ordered_at': orderedAt.toUtc(),
  };

  Map<String, Object?> toJson({String? cashierName}) => {
    'id': idHex(id),
    'receipt_number': receiptNumber,
    'cashier_id': idHex(cashierId),
    'cashier_name': cashierName,
    'platform': platform,
    'total_price': totalPrice,
    'items': [for (final item in items) item.toJson()],
    'ordered_at': orderedAt.toIso8601String(),
  };
}
