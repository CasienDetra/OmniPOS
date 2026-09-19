// Ensures the `files` collection exists with a unique index on `filename`.
// Usage: dart run scripts/seed.dart
import 'package:pos_file/pos_file.dart';

Future<void> main() async {
  final db = await MongoDb.instance.database;
  await db.runCommand({
    'createIndexes': 'files',
    'indexes': [
      {
        'key': {'filename': 1},
        'name': 'filename_unique',
        'unique': true,
      },
    ],
  });
  print('pos_file: collection "files" ready (unique index on filename).');
  await MongoDb.instance.close();
}
