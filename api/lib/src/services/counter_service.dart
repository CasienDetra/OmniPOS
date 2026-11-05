import '../core/exceptions.dart';
import '../database/mongo_db.dart';

/// Sequential 7-digit receipt numbers via an atomic counter document
/// (replaces v4's race-prone random generator).
class CounterService {
  static const _firstReceipt = 1000000;

  Future<String> nextReceiptNumber() async {
    final seq = await _nextSeq('receipt');
    return '${(_firstReceipt + seq) % 10000000}'.padLeft(7, '0');
  }

  /// A transaction id for the payment gateway: 13 characters, inside the 20
  /// PayWay allows.
  ///
  /// Uniqueness here is measured against the *gateway's* history, not this
  /// database's: PayWay refuses a repeated id with `4: Duplicated transaction
  /// ID`, and it does not know that the shop re-seeded its database yesterday.
  /// Prefixing the UTC date makes an id from one day unrepeatable on another,
  /// and the counter separates ids issued within the same day.
  Future<String> nextPaymentTranId() async {
    final seq = await _nextSeq('payment');
    final now = DateTime.now().toUtc();
    String pad(int value) => value.toString().padLeft(2, '0');
    final day = '${pad(now.year % 100)}${pad(now.month)}${pad(now.day)}';
    return '$day${(1000001 + seq) % 10000000}';
  }

  Future<int> _nextSeq(String key) async {
    final db = await MongoDb.instance.database;
    // One round trip that increments and hands back the new value. Incrementing
    // and then reading lets two tills that ask at the same moment both read the
    // higher of their two numbers, and one of them is issued a duplicate.
    final doc = await db
        .collection('counters')
        .findAndModify(
          query: {'_id': key},
          update: {
            r'$inc': {'seq': 1},
          },
          upsert: true,
          returnNew: true,
        );
    final seq = (doc?['seq'] as num?)?.toInt();
    if (seq == null) {
      throw InternalServerException('Failed to generate counter "$key"');
    }
    return seq;
  }
}
