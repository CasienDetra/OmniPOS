import 'dart:async';
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart';

import '../config/app_config.dart';
import '../core/exceptions.dart';

class MongoDb {
  MongoDb._();

  static final MongoDb instance = MongoDb._();

  Db? _db;

  Future<Db> get database async {
    try {
      var db = _db;
      if (db == null) {
        db = await Db.create(AppConfig.current.mongoUri)
            .timeout(const Duration(seconds: 5));
        await db.open().timeout(const Duration(seconds: 5));
        _db = db;
      }
      await db.pingCommand().timeout(const Duration(seconds: 3));
      return db;
    } on AppException {
      rethrow;
    } on TimeoutException {
      _db = null;
      throw const DatabaseConnectionFailedException();
    } on SocketException {
      _db = null;
      throw const DatabaseConnectionFailedException();
    } catch (_) {
      _db = null;
      throw const DatabaseConnectionFailedException();
    }
  }

  Future<DbCollection> collection(String name) async =>
      (await database).collection(name);

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await db.close();
  }
}
