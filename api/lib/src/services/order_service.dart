import 'dart:convert';

import 'package:mongo_dart/mongo_dart.dart';

import '../core/auth.dart';
import '../core/exceptions.dart';
import '../core/pagination.dart';
import '../models/order.dart';
import '../models/product.dart';
import '../models/user.dart';
import '../repositories/mongo.dart';
import 'counter_service.dart';

const _saleSortFields = {
  'ordered_at': 'ordered_at',
  'total_price': 'total_price',
  'receipt_number': 'receipt_number',
};

class OrderService {
  OrderService({CounterService? counters})
    : _counters = counters ?? CounterService();

  final CounterService _counters;

  /// Checkout (v4 c1-order service): parse the cart JSON map
  /// `{productId: qty}`, snapshot prices, persist one embedded order doc.
  Future<Order> createOrder({
    required String cart,
    required String platform,
    required ObjectId cashierId,
  }) async {
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(cart);
      if (decoded is! Map) throw const FormatException();
      parsed = decoded.cast<String, dynamic>();
    } on FormatException {
      throw InvalidEntityException(['cart must be a JSON object']);
    }
    if (parsed.isEmpty) {
      throw InvalidEntityException(['cart must not be empty']);
    }

    final items = <OrderItem>[];
    var totalPrice = 0.0;
    for (final entry in parsed.entries) {
      final qty = entry.value is num ? (entry.value as num).toInt() : 0;
      if (qty <= 0) {
        throw InvalidEntityException(['qty for "${entry.key}" must be > 0']);
      }
      final product = await getActiveProduct(entry.key);
      final linePrice = product.unitPrice * qty;
      totalPrice += linePrice;
      items.add(
        OrderItem(
          productId: entry.key,
          name: product.name,
          unitPrice: product.unitPrice,
          qty: qty,
        ),
      );
    }

    final order = Order(
      receiptNumber: await _counters.nextReceiptNumber(),
      cashierId: cashierId,
      platform: platform.isEmpty ? 'Web' : platform,
      totalPrice: double.parse(totalPrice.toStringAsFixed(2)),
      items: items,
      orderedAt: DateTime.now().toUtc(),
    );
    final id = await insertDoc('orders', order.toDocument());
    return Order(
      id: id,
      receiptNumber: order.receiptNumber,
      cashierId: order.cashierId,
      platform: order.platform,
      totalPrice: order.totalPrice,
      items: order.items,
      orderedAt: order.orderedAt,
    );
  }

  Future<Product> getActiveProduct(String rawId) async {
    final doc = await findDoc('products', {'_id': asObjectId(rawId)});
    if (doc == null) {
      throw NotFoundException('Product "$rawId" not found');
    }
    final product = Product.fromDocument(doc);
    if (!product.isActive) {
      throw ConflictException('Product "${product.name}" is not active');
    }
    return product;
  }

  Future<Map<String, Object?>> list({
    required int page,
    required int limit,
    String? key,
    AuthUser? cashier,
    ObjectId? cashierId,
    String? platform,
    DateTime? startDate,
    DateTime? endDate,
    String sortBy = 'ordered_at',
    bool ascending = false,
  }) async {
    final filter = <String, Object?>{
      if (key != null)
        'receipt_number': RegExp(RegExp.escape(key), caseSensitive: false),
      if (cashierId != null) 'cashier_id': cashierId,
      if (platform != null) 'platform': platform,
      if (startDate != null || endDate != null)
        'ordered_at': {
          if (startDate != null) r'$gte': startDate,
          if (endDate != null) r'$lte': endDate,
        },
    };

    final total = await countDocs('orders', filter);
    final sortField = _saleSortFields[sortBy] ?? 'ordered_at';
    final docs = await findPage(
      collection: 'orders',
      filter: filter,
      sort: {sortField: ascending ? 1 : -1},
      skip: (page - 1) * limit,
      limit: limit,
    );

    final cashierIds = docs
        .map((doc) => doc['cashier_id'])
        .whereType<ObjectId>()
        .toSet()
        .toList();
    final cashierNames = <String, String>{};
    if (cashierIds.isNotEmpty) {
      final users = await findPage(
        collection: 'users',
        filter: {
          '_id': {r'$in': cashierIds},
        },
        limit: cashierIds.length,
      );
      for (final user in users) {
        cashierNames[user['_id'].toString()] = User.fromDocument(user).name;
      }
    }

    return {
      'data': [
        for (final doc in docs)
          Order.fromDocument(doc).toJson(
            cashierName: cashierNames[doc['cashier_id']?.toString()],
          ),
      ],
      'pagination': buildPagination(page: page, limit: limit, total: total),
    };
  }

  Future<Order> get(String rawId) async {
    final doc = await findDoc('orders', {'_id': asObjectId(rawId)});
    if (doc == null) {
      throw NotFoundException('Sale "$rawId" not found');
    }
    return Order.fromDocument(doc);
  }

  /// Detail view with the cashier name resolved (v4 Sequelize include).
  Future<Map<String, Object?>> getJson(String rawId) async {
    final order = await get(rawId);
    final cashierDoc = await findDoc('users', {'_id': order.cashierId});
    return order.toJson(cashierName: cashierDoc?['name'] as String?);
  }

  /// Cashier may only touch their own sales (v4 filtered by cashier_id).
  Future<Order> getFor({
    required String rawId,
    required ObjectId cashier,
  }) async {
    final order = await get(rawId);
    if (order.cashierId != cashier) {
      throw const ForbiddenException('This sale belongs to another cashier');
    }
    return order;
  }

  Future<void> delete(String rawId) async {
    await get(rawId);
    await deleteById('orders', rawId);
  }
}
