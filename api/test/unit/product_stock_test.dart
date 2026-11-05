import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

Product _product({int? stock, int? threshold}) => Product(
  name: 'Rice',
  code: 'P1',
  typeId: null,
  unitPrice: 1000,
  image: '',
  isActive: true,
  creatorId: null,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
  stock: stock,
  lowStockThreshold: threshold,
);

void main() {
  group('Product.isLowStock', () {
    test('an untracked product is never low', () {
      expect(_product().isLowStock, isFalse);
      expect(_product(threshold: 5).isLowStock, isFalse);
    });

    test('nothing left is low whatever the threshold says', () {
      expect(_product(stock: 0).isLowStock, isTrue);
      expect(_product(stock: 0, threshold: 0).isLowStock, isTrue);
      expect(_product(stock: -1).isLowStock, isTrue);
    });

    test('at or below the threshold is low', () {
      expect(_product(stock: 3, threshold: 3).isLowStock, isTrue);
      expect(_product(stock: 2, threshold: 3).isLowStock, isTrue);
      expect(_product(stock: 4, threshold: 3).isLowStock, isFalse);
    });

    test('without a threshold only nothing-left is low', () {
      expect(_product(stock: 1).isLowStock, isFalse);
      expect(_product(stock: 1, threshold: null).isLowStock, isFalse);
    });
  });

  group('Product stock persistence', () {
    test('stock and threshold survive a document round trip', () {
      final restored = Product.fromDocument(
        _product(stock: 4, threshold: 5).toDocument(),
      );
      expect(restored.stock, 4);
      expect(restored.lowStockThreshold, 5);
    });

    test('an untracked product stores no stock figure', () {
      final doc = _product().toDocument();
      expect(doc['stock'], isNull);
      expect(doc['low_stock_threshold'], isNull);
      expect(Product.fromDocument(doc).stock, isNull);
    });

    test('the API body carries the figures a screen needs to warn', () {
      final json = _product(stock: 2, threshold: 5).toJson();
      expect(json['stock'], 2);
      expect(json['low_stock_threshold'], 5);
    });
  });

  group('Validator.optionalInt', () {
    test('reads a count, rejects junk, and enforces the floor', () {
      final valid = Validator();
      expect(valid.optionalInt({'stock': 4}, 'stock', min: 0), 4);
      expect(valid.optionalInt({}, 'stock', min: 0), isNull);
      expect(valid.errors, isEmpty);

      final junk = Validator();
      expect(junk.optionalInt({'stock': 'x'}, 'stock', min: 0), isNull);
      expect(junk.errors, contains('stock must be an integer'));

      final negative = Validator();
      expect(negative.optionalInt({'stock': -1}, 'stock', min: 0), isNull);
      expect(negative.errors, contains('stock must be at least 0'));
    });
  });
}
