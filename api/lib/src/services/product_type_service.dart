import '../core/exceptions.dart';
import '../core/pagination.dart';
import '../models/product_type.dart';
import '../repositories/mongo.dart';

class ProductTypeService {
  const ProductTypeService();

  Future<List<ProductType>> all() async {
    final docs = await findPage(
      collection: 'product_types',
      sort: {'name': 1},
      limit: 200,
    );
    return [for (final doc in docs) ProductType.fromDocument(doc)];
  }

  Future<Map<String, Object?>> list({
    required int page,
    required int limit,
  }) async {
    final total = await countDocs('product_types');
    final docs = await findPage(
      collection: 'product_types',
      sort: {'name': 1},
      skip: (page - 1) * limit,
      limit: limit,
    );
    return {
      'data': [for (final doc in docs) ProductType.fromDocument(doc).toJson()],
      'pagination': buildPagination(page: page, limit: limit, total: total),
    };
  }

  Future<ProductType> get(String rawId) async {
    final doc = await findDoc('product_types', {'_id': asObjectId(rawId)});
    if (doc == null) {
      throw NotFoundException('Product type "$rawId" not found');
    }
    return ProductType.fromDocument(doc);
  }

  Future<ProductType> create(String name) async {
    await _ensureNameUnique(name);
    final now = DateTime.now().toUtc();
    final type = ProductType(name: name, createdAt: now, updatedAt: now);
    final id = await insertDoc('product_types', type.toDocument());
    return ProductType(id: id, name: name, createdAt: now, updatedAt: now);
  }

  Future<void> update(String rawId, String name) async {
    await get(rawId);
    await _ensureNameUnique(name, excludeId: rawId);
    await updateById('product_types', rawId, {
      'name': name,
      'updated_at': DateTime.now().toUtc(),
    });
  }

  Future<void> delete(String rawId) async {
    await get(rawId);
    final inUse = await countDocs('products', {'type_id': asObjectId(rawId)});
    if (inUse > 0) {
      throw ConflictException(
        'Type is used by $inUse product(s); move them first',
      );
    }
    await deleteById('product_types', rawId);
  }

  Future<void> _ensureNameUnique(String name, {String? excludeId}) async {
    final clash = await findDoc('product_types', {
      'name': name,
      if (excludeId != null) '_id': {r'$ne': asObjectId(excludeId)},
    });
    if (clash != null) {
      throw ConflictException('Product type "$name" already exists');
    }
  }
}
