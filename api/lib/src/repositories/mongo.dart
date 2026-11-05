import 'package:mongo_dart/mongo_dart.dart';

import '../core/pagination.dart';
import '../database/mongo_db.dart';

/// Thin data-access helpers shared by all services (the "repository" layer
/// that v4 expressed with per-module Sequelize models).
Future<List<Map<String, dynamic>>> findPage({
  required String collection,
  Map<String, Object?> filter = const {},
  Map<String, Object?> sort = const {},
  int skip = 0,
  int limit = 10,
}) async {
  final db = await MongoDb.instance.database;
  return db
      .collection(collection)
      .modernFind(
        filter: filter,
        sort: sort.isEmpty ? null : Map<String, Object>.from(sort),
        skip: skip > 0 ? skip : null,
        limit: limit,
      )
      .toList();
}

Future<int> countDocs(
  String collection, [
  Map<String, Object?> filter = const {},
]) async {
  final db = await MongoDb.instance.database;
  return db.collection(collection).count(filter);
}

Future<Map<String, dynamic>?> findDoc(
  String collection,
  Map<String, Object?> filter,
) async {
  final db = await MongoDb.instance.database;
  return db.collection(collection).findOne(filter);
}

Future<ObjectId> insertDoc(
  String collection,
  Map<String, Object?> document,
) async {
  final db = await MongoDb.instance.database;
  final doc = Map<String, Object?>.from(document);
  final oid = ObjectId();
  doc['_id'] = oid;
  await db.collection(collection).insertOne(doc);
  return oid;
}

Future<int> updateById(
  String collection,
  String rawId,
  Map<String, Object?> setFields,
) async {
  final db = await MongoDb.instance.database;
  final result = await db
      .collection(collection)
      .updateOne({'_id': asObjectId(rawId)}, {r'$set': setFields});
  return result.nModified;
}

/// Applies `$set` only to documents that still match [filter] and reports how
/// many moved — the primitive a state transition needs.
///
/// Updating a document by id and writing its new status is a check-then-write:
/// two payment confirmations that race would both read `pending`, both write
/// `paid`, and both go on to create a Sale. Filtering on the status the caller
/// observed makes the second one match nothing, so it learns it lost instead of
/// acting as if it won. Every transition here sets a field the filter excludes,
/// so `nModified` cannot be confused with a matched-but-identical write.
Future<int> updateWhere(
  String collection,
  Map<String, Object?> filter,
  Map<String, Object?> setFields,
) async {
  final db = await MongoDb.instance.database;
  final result = await db.collection(collection).updateOne(filter, {
    r'$set': setFields,
  });
  return result.nModified;
}

/// Applies `$inc` to documents that still match [filter] and reports how many
/// moved — the primitive a stock take needs.
///
/// A decrement guarded by `stock: {$gte: qty}` either happens or matches
/// nothing, so two tills cannot sell the same last unit.
Future<int> incrementWhere(
  String collection,
  Map<String, Object?> filter,
  Map<String, Object?> incFields,
) async {
  final db = await MongoDb.instance.database;
  final result = await db.collection(collection).updateOne(filter, {
    r'$inc': incFields,
  });
  return result.nModified;
}

Future<int> deleteById(String collection, String rawId) async {
  final db = await MongoDb.instance.database;
  final result = await db.collection(collection).deleteOne({
    '_id': asObjectId(rawId),
  });
  return result.nRemoved;
}

Future<void> deleteDocs(String collection, Map<String, Object?> filter) async {
  final db = await MongoDb.instance.database;
  await db.collection(collection).deleteMany(filter);
}

Future<List<Map<String, dynamic>>> aggregate(
  String collection,
  List<Map<String, Object?>> pipeline,
) async {
  final db = await MongoDb.instance.database;
  return db.collection(collection).aggregateToStream([
    for (final stage in pipeline) stage.cast<String, Object>(),
  ]).toList();
}
