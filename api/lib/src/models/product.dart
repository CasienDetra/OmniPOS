import 'package:mongo_dart/mongo_dart.dart';

import '../core/pagination.dart';

class Product {
  const Product({
    this.id,
    required this.name,
    required this.code,
    required this.typeId,
    required this.unitPrice,
    required this.image,
    required this.isActive,
    required this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    this.stock,
    this.lowStockThreshold,
  });

  static Product fromDocument(Map<String, dynamic> doc) => Product(
    id: doc['_id'] as ObjectId?,
    name: doc['name'] as String? ?? '',
    code: doc['code'] as String? ?? '',
    typeId: doc['type_id'] as ObjectId?,
    unitPrice: (doc['unit_price'] as num?)?.toDouble() ?? 0,
    image: doc['image'] as String? ?? '',
    isActive: doc['is_active'] != false,
    creatorId: doc['creator_id'] as ObjectId?,
    createdAt: doc['created_at'] as DateTime? ?? DateTime.now(),
    updatedAt: doc['updated_at'] as DateTime? ?? DateTime.now(),
    stock: (doc['stock'] as num?)?.toInt(),
    lowStockThreshold: (doc['low_stock_threshold'] as num?)?.toInt(),
  );

  final ObjectId? id;
  final String name;
  final String code;
  final ObjectId? typeId;
  final double unitPrice;
  final String image;
  final bool isActive;
  final ObjectId? creatorId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Units on hand. Null means this product is not stock-tracked: it can be
  /// sold without limit and can never be reported as low.
  final int? stock;

  /// Warn at or below this many units. Null means only zero is a warning.
  final int? lowStockThreshold;

  bool get isLowStock {
    final onHand = stock;
    if (onHand == null) return false;
    if (onHand <= 0) return true;
    final threshold = lowStockThreshold;
    return threshold != null && onHand <= threshold;
  }

  Map<String, Object?> toDocument() => {
    'name': name,
    'code': code,
    'type_id': typeId,
    'unit_price': unitPrice,
    'image': image,
    'is_active': isActive,
    'creator_id': creatorId,
    'created_at': createdAt.toUtc(),
    'updated_at': updatedAt.toUtc(),
    'stock': stock,
    'low_stock_threshold': lowStockThreshold,
  };

  Map<String, Object?> toJson({String? typeName, String? creatorName}) => {
    'id': idHex(id),
    'name': name,
    'code': code,
    'type_id': idHex(typeId),
    'type_name': typeName,
    'unit_price': unitPrice,
    'image': image,
    'is_active': isActive,
    'creator_id': idHex(creatorId),
    'creator_name': creatorName,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'stock': stock,
    'low_stock_threshold': lowStockThreshold,
  };
}
