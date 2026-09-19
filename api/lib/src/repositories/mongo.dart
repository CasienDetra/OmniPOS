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

Future<int> countDocs(String collection, [Map<String, Object?> filter = const {}]) async {
  final db = await MongoDb.instance.database;
  return db.collection(collection).count(filter);
}

Future<Map<String, dynamic>?> findDoc(
    String collection, Map<String, Object?> filter) async {
  final db = await MongoDb.instance.database;
  return db.collection(collection).findOne(filter);
}

Future<ObjectId> insertDoc(
    String collection, Map<String, Object?> document) async {
  final db = await MongoDb.instance.database;
  final doc = Map<String, Object?>.from(document);
  final oid = ObjectId();
  doc['_id'] = oid;
  await db.collection(collection).insertOne(doc);
  return oid;
}

Future<int> updateById(
    String collection, String rawId, Map<String, Object?> setFields) async {
  final db = await MongoDb.instance.database;
  final result = await db.collection(collection).updateOne(
        {'_id': asObjectId(rawId)},
        {r'$set': setFields},
      );
  return result.nModified;
}

Future<int> deleteById(String collection, String rawId) async {
  final db = await MongoDb.instance.database;
  final result =
      await db.collection(collection).deleteOne({'_id': asObjectId(rawId)});
  return result.nRemoved;
}

Future<void> deleteDocs(String collection, Map<String, Object?> filter) async {
  final db = await MongoDb.instance.database;
  await db.collection(collection).deleteMany(filter);
}

Future<List<Map<String, dynamic>>> aggregate(
    String collection, List<Map<String, Object?>> pipeline) async {
  final db = await MongoDb.instance.database;
  return db
      .collection(collection)
      .aggregateToStream(
          [for (final stage in pipeline) stage.cast<String, Object>()])
      .toList();
}
