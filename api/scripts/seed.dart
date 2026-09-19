// Seeds indexes, default users and sample catalogue data.
// Usage: dart run scripts/seed.dart  (idempotent; re-run safe)
import 'package:mongo_dart/mongo_dart.dart';
import 'package:pos_api/pos_api.dart';

Future<void> main() async {
  final db = await MongoDb.instance.database;

  await _createIndexes(db);
  final adminId = await _ensureUser(
    name: 'Administrator',
    phone: '080000000001',
    email: 'admin@pos.local',
    password: 'admin123',
    roleIds: const [Role.admin],
  );
  await _ensureUser(
    name: 'Cashier One',
    phone: '080000000002',
    email: 'cashier@pos.local',
    password: 'cashier123',
    roleIds: const [Role.cashier],
  );

  final foodId = await _ensureType('Food');
  final drinkId = await _ensureType('Drink');
  await _ensureProduct(foodId, adminId, 'Nasi Goreng', 'P0001', 15000);
  await _ensureProduct(foodId, adminId, 'Mie Ayam', 'P0002', 12000);
  await _ensureProduct(drinkId, adminId, 'Es Teh Manis', 'P0003', 5000);
  await _ensureProduct(drinkId, adminId, 'Air Mineral', 'P0004', 3000);

  print('pos_api seed done: admin@pos.local/admin123, '
      'cashier@pos.local/cashier123, 2 types, 4 products.');
  await MongoDb.instance.close();
}

Future<void> _createIndexes(Db db) async {
  Future<void> ensure(String collection, List<Map<String, Object>> indexes) =>
      db.runCommand({
        'createIndexes': collection,
        'indexes': indexes,
      });

  await ensure('users', [
    {
      'key': {'email': 1},
      'name': 'email_unique',
      'unique': true,
    },
    {
      'key': {'phone': 1},
      'name': 'phone_unique',
      'unique': true,
    },
  ]);
  await ensure('product_types', [
    {
      'key': {'name': 1},
      'name': 'name_unique',
      'unique': true,
    },
  ]);
  await ensure('products', [
    {
      'key': {'code': 1},
      'name': 'code_unique',
      'unique': true,
    },
  ]);
  await ensure('orders', [
    {
      'key': {'receipt_number': 1},
      'name': 'receipt_unique',
      'unique': true,
    },
    {
      'key': {'cashier_id': 1, 'ordered_at': -1},
      'name': 'cashier_date',
    },
  ]);
  await ensure('user_logs', [
    {
      'key': {'user_id': 1, 'timestamp': -1},
      'name': 'user_time',
    },
  ]);
  print('indexes ready.');
}

Future<ObjectId> _ensureUser({
  required String name,
  required String phone,
  required String email,
  required String password,
  required List<int> roleIds,
}) async {
  final existing = await findDoc('users', {'email': email});
  if (existing != null) return existing['_id'] as ObjectId;
  final now = DateTime.now().toUtc();
  final id = await insertDoc('users', {
    'name': name,
    'phone': phone,
    'email': email,
    'password': AuthService.hashPassword(password),
    'avatar': null,
    'is_active': true,
    'roles': [
      for (final (index, roleId) in roleIds.indexed)
        {
          'id': roleId,
          'name': Role.names[roleId],
          'is_default': index == 0,
        },
    ],
    'created_at': now,
    'updated_at': now,
    'last_login': null,
  });
  print('created user $email');
  return id;
}

Future<ObjectId> _ensureType(String name) async {
  final existing = await findDoc('product_types', {'name': name});
  if (existing != null) return existing['_id'] as ObjectId;
  final now = DateTime.now().toUtc();
  final id = await insertDoc('product_types', {
    'name': name,
    'created_at': now,
    'updated_at': now,
  });
  print('created product type $name');
  return id;
}

Future<void> _ensureProduct(
  ObjectId typeId,
  ObjectId creatorId,
  String name,
  String code,
  double unitPrice,
) async {
  final existing = await findDoc('products', {'code': code});
  if (existing != null) return;
  final now = DateTime.now().toUtc();
  await insertDoc('products', {
    'name': name,
    'code': code,
    'type_id': typeId,
    'unit_price': unitPrice,
    'image': '',
    'is_active': true,
    'creator_id': creatorId,
    'created_at': now,
    'updated_at': now,
  });
  print('created product $code ($name)');
}
