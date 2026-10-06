import '../core/exceptions.dart';
import '../database/mongo_db.dart';

/// Sequential 7-digit receipt numbers via an atomic counter document
/// (replaces v4's race-prone random generator).
class CounterService {
  static const _firstReceipt = 1000000;

  Future<String> nextReceiptNumber() async {
    final db = await MongoDb.instance.database;
    final counters = db.collection('counters');
    await counters.updateOne(
      {'_id': 'receipt'},
      {
        r'$inc': {'seq': 1},
      },
      upsert: true,
    );
    final doc = await counters.findOne({'_id': 'receipt'});
    final seq = (doc?['seq'] as num?)?.toInt();
    if (seq == null) {
      throw const InternalServerException('Failed to generate receipt number');
    }
    return '${(_firstReceipt + seq) % 10000000}'.padLeft(7, '0');
  }
}
