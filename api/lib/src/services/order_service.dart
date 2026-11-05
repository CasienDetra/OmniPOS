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

/// A cart with its prices snapshotted from the catalogue, and the total the
/// customer owes for it.
typedef PricedCart = ({List<OrderItem> items, double totalPrice});

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
    final priced = await priceCart(cart);
    return createSale(
      items: priced.items,
      totalPrice: priced.totalPrice,
      cashierId: cashierId,
      platform: platform,
    );
  }

  /// Parse a cart and snapshot the catalogue prices onto its lines, without
  /// persisting anything.
  ///
  /// Split out because a QR must be generated for the amount the Sale will
  /// actually be: if the payment module priced a cart by itself and the rules
  /// ever drifted, the customer would scan a code that does not match its own
  /// receipt.
  Future<PricedCart> priceCart(String cart) async {
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
      final stock = product.stock;
      if (stock != null && stock < qty) {
        throw ConflictException(
          'Only $stock of "${product.name}" left; $qty were requested',
        );
      }
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
    return (
      items: items,
      totalPrice: double.parse(totalPrice.toStringAsFixed(2)),
    );
  }

  /// Persist one completed Sale.
  ///
  /// A Sale paid by QR passes the gateway's [paymentTranId], and that is the
  /// only guard that matters: two confirmations of the same transaction — the
  /// notification racing the cashier's poll — must not print two receipts, and
  /// the unique partial index on `payment_tran_id` makes the second insert
  /// impossible rather than merely unlikely.
  Future<Order> createSale({
    required List<OrderItem> items,
    required double totalPrice,
    required ObjectId cashierId,
    required String platform,
    String? paymentTranId,
    bool enforceStock = true,
  }) async {
    // Stock is taken before the Sale is written, for a cash sale and a QR
    // confirmation alike. A refused cash sale therefore never draws a receipt
    // number, and a losing writer in the duplicate-key race puts its take back
    // instead of shrinking the shelf.
    await _takeStock(items, enforce: enforceStock);

    // The counter is a separate write and can fail on its own. Without this
    // guard the stock would stay decremented with no Sale to account for it.
    final String receiptNumber;
    try {
      receiptNumber = await _counters.nextReceiptNumber();
    } catch (_) {
      await _releaseStock(items);
      rethrow;
    }

    final order = Order(
      receiptNumber: receiptNumber,
      cashierId: cashierId,
      platform: platform.isEmpty ? 'Web' : platform,
      totalPrice: totalPrice,
      items: items,
      orderedAt: DateTime.now().toUtc(),
      paymentTranId: paymentTranId,
    );
    final ObjectId id;
    try {
      id = await insertDoc('orders', order.toDocument());
    } catch (_) {
      await _releaseStock(items);
      rethrow;
    }

    return Order(
      id: id,
      receiptNumber: order.receiptNumber,
      cashierId: order.cashierId,
      platform: order.platform,
      totalPrice: order.totalPrice,
      items: order.items,
      orderedAt: order.orderedAt,
      paymentTranId: order.paymentTranId,
    );
  }

  /// Decrements tracked products. With [enforce], a line that would go below
  /// zero is refused; without it the decrement always lands, which is what a
  /// QR payment needs once the money has moved. Untracked products carry no
  /// `stock` field and are left alone.
  ///
  /// If a later line is refused, the lines already taken are put back, so one
  /// half-sold cart cannot quietly shrink the shelf.
  Future<void> _takeStock(
    List<OrderItem> items, {
    required bool enforce,
  }) async {
    final taken = <OrderItem>[];
    try {
      for (final item in items) {
        final productId = asObjectId(item.productId);
        final modified = await incrementWhere(
          'products',
          {
            '_id': productId,
            'stock': {r'$ne': null, if (enforce) r'$gte': item.qty},
          },
          {'stock': -item.qty},
        );
        if (modified > 0) {
          taken.add(item);
          continue;
        }
        if (!enforce) continue;
        final doc = await findDoc('products', {'_id': productId});
        final stock = (doc?['stock'] as num?)?.toInt();
        if (stock != null) {
          throw ConflictException(
            'Only $stock of "${item.name}" left; ${item.qty} were requested',
          );
        }
      }
    } catch (_) {
      await _releaseStock(taken);
      rethrow;
    }
  }

  /// Puts back what [_takeStock] took. Untracked products are untouched.
  Future<void> _releaseStock(List<OrderItem> items) async {
    for (final item in items) {
      await incrementWhere(
        'products',
        {
          '_id': asObjectId(item.productId),
          'stock': {r'$ne': null},
        },
        {'stock': item.qty},
      );
    }
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
          Order.fromDocument(
            doc,
          ).toJson(cashierName: cashierNames[doc['cashier_id']?.toString()]),
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
