import 'package:mongo_dart/mongo_dart.dart';

import '../core/exceptions.dart';
import '../core/pagination.dart';
import '../models/product.dart';
import '../models/product_type.dart';
import '../models/user.dart';
import '../repositories/mongo.dart';
import 'file_service.dart';

/// Sort whitelist prevents injection through `sort_by` (v4 relied on
/// class-validator; here we map explicitly).
const _productSortFields = {
  'name': 'name',
  'code': 'code',
  'unit_price': 'unit_price',
  'created_at': 'created_at',
  'updated_at': 'updated_at',
};

class ProductService {
  ProductService({FileService? fileService})
    : _fileService = fileService ?? FileService();

  final FileService _fileService;

  Future<Map<String, Object?>> setupData() async {
    final types = await findPage(
      collection: 'product_types',
      sort: {'name': 1},
      limit: 200,
    );
    final users = await findPage(
      collection: 'users',
      sort: {'name': 1},
      limit: 200,
    );
    return {
      'productTypes': [
        for (final doc in types) ProductType.fromDocument(doc).toRefJson(),
      ],
      'users': [for (final doc in users) User.fromDocument(doc).toRefJson()],
    };
  }

  Future<Map<String, Object?>> list({
    required int page,
    required int limit,
    String? key,
    String? type,
    String? creator,
    DateTime? startDate,
    DateTime? endDate,
    String sortBy = 'name',
    bool ascending = true,
    bool activeOnly = false,
  }) async {
    final filter = <String, Object?>{
      if (key != null)
        r'$or': [
          {'name': RegExp(RegExp.escape(key), caseSensitive: false)},
          {'code': RegExp(RegExp.escape(key), caseSensitive: false)},
        ],
      if (type != null) 'type_id': asObjectId(type),
      if (creator != null) 'creator_id': asObjectId(creator),
      if (activeOnly) 'is_active': true,
      if (startDate != null || endDate != null)
        'created_at': {
          if (startDate != null) r'$gte': startDate,
          if (endDate != null) r'$lte': endDate,
        },
    };

    final total = await countDocs('products', filter);
    final sortField = _productSortFields[sortBy] ?? 'name';
    final docs = await findPage(
      collection: 'products',
      filter: filter,
      sort: {sortField: ascending ? 1 : -1},
      skip: (page - 1) * limit,
      limit: limit,
    );

    final typeNames = await _lookupNames('product_types', docs, 'type_id');
    final creatorNames = await _lookupNames('users', docs, 'creator_id');

    return {
      'data': [
        for (final doc in docs)
          Product.fromDocument(doc).toJson(
            typeName: typeNames[doc['type_id']?.toString()],
            creatorName: creatorNames[doc['creator_id']?.toString()],
          ),
      ],
      'pagination': buildPagination(page: page, limit: limit, total: total),
    };
  }

  Future<Product> get(String rawId) async {
    final doc = await findDoc('products', {'_id': asObjectId(rawId)});
    if (doc == null) {
      throw NotFoundException('Product "$rawId" not found');
    }
    return Product.fromDocument(doc);
  }

  /// Detail view with joined type/creator names (v4 used Sequelize includes).
  Future<Map<String, Object?>> getJson(String rawId) async {
    final product = await get(rawId);
    final typeDoc = await findDoc('product_types', {'_id': product.typeId});
    final creatorDoc = await findDoc('users', {'_id': product.creatorId});
    return product.toJson(
      typeName: typeDoc?['name'] as String?,
      creatorName: creatorDoc?['name'] as String?,
    );
  }

  /// Creates a product; when `image` holds a base64 data-URL it is pushed to
  /// the file service and only the relative uri is stored (v4 behaviour).
  Future<Product> create({
    required String name,
    required String code,
    required ObjectId typeId,
    required double unitPrice,
    String? image,
    ObjectId? creatorId,
    bool isActive = true,
  }) async {
    await _ensureCodeUnique(code);
    final imageUrl = (image == null || image.isEmpty)
        ? ''
        : await _uploadImage(image);
    final now = DateTime.now().toUtc();
    final product = Product(
      name: name,
      code: code,
      typeId: typeId,
      unitPrice: unitPrice,
      image: imageUrl,
      isActive: isActive,
      creatorId: creatorId,
      createdAt: now,
      updatedAt: now,
    );
    final id = await insertDoc('products', product.toDocument());
    return Product(
      id: id,
      name: name,
      code: code,
      typeId: typeId,
      unitPrice: unitPrice,
      image: imageUrl,
      isActive: isActive,
      creatorId: creatorId,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> update(
    String rawId, {
    String? name,
    String? code,
    ObjectId? typeId,
    double? unitPrice,
    String? image,
    bool? isActive,
  }) async {
    final existing = await get(rawId);
    final fields = <String, Object?>{
      if (name != null) 'name': name,
      if (typeId != null) 'type_id': typeId,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (isActive != null) 'is_active': isActive,
    };
    if (code != null && code != existing.code) {
      await _ensureCodeUnique(code, excludeId: rawId);
      fields['code'] = code;
    }
    if (image != null && image.isNotEmpty) {
      fields['image'] = await _uploadImage(image);
    }
    if (fields.isEmpty) return;
    fields['updated_at'] = DateTime.now().toUtc();
    await updateById('products', rawId, fields);
  }

  Future<void> delete(String rawId) async {
    await get(rawId);
    await deleteById('products', rawId);
  }

  Future<String> _uploadImage(String base64Image) async {
    final data = await _fileService.uploadBase64Image('product', base64Image);
    return data['uri'] as String? ?? '';
  }

  Future<void> _ensureCodeUnique(String code, {String? excludeId}) async {
    final clash = await findDoc('products', {
      'code': code,
      if (excludeId != null) '_id': {r'$ne': asObjectId(excludeId)},
    });
    if (clash != null) {
      throw ConflictException('Product code "$code" already exists');
    }
  }

  Future<Map<String, String>> _lookupNames(
    String collection,
    List<Map<String, dynamic>> docs,
    String field,
  ) async {
    final ids = docs
        .map((doc) => doc[field])
        .whereType<ObjectId>()
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    final found = await findPage(
      collection: collection,
      filter: {
        '_id': {r'$in': ids},
      },
      limit: ids.length,
    );
    return {
      for (final doc in found) doc['_id'].toString(): doc['name'] as String,
    };
  }
}
