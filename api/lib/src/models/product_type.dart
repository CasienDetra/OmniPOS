import 'package:mongo_dart/mongo_dart.dart';

import '../core/pagination.dart';

class ProductType {
  const ProductType({
    this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
  });

  static ProductType fromDocument(Map<String, dynamic> doc) => ProductType(
    id: doc['_id'] as ObjectId?,
    name: doc['name'] as String? ?? '',
    createdAt: doc['created_at'] as DateTime? ?? DateTime.now(),
    updatedAt: doc['updated_at'] as DateTime? ?? DateTime.now(),
  );

  final ObjectId? id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toDocument() => {
    'name': name,
    'created_at': createdAt.toUtc(),
    'updated_at': updatedAt.toUtc(),
  };

  Map<String, Object?> toJson() => {
    'id': idHex(id),
    'name': name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Map<String, Object?> toRefJson() => {'id': idHex(id), 'name': name};
}
