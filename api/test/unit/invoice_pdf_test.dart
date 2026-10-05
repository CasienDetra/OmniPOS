import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

Map<String, Object?> _fixtureOrder() => {
  'id': '6ab11f855dc3537029037fad',
  'receipt_number': '1000002',
  'cashier_id': '6aae2db74de6be2963979eed',
  'cashier_name': 'Cashier One',
  'platform': 'Web',
  'total_price': 6000,
  'items': [
    {
      'product_id': '6aae2db74de6be2963979eee',
      'name': 'បាយប្រោម',
      'unit_price': 2000,
      'qty': 3,
      'line_price': 6000,
    },
  ],
  'ordered_at': '2026-10-05T07:30:00.000Z',
};

void main() {
  test('renders an A4 PDF from an order payload', () async {
    final bytes = await InvoicePdfService().render(_fixtureOrder());
    final header = String.fromCharCodes(bytes.take(5));
    expect(header, '%PDF-');
    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.skip(bytes.length - 10)),
      contains('%%EOF'),
    );
  });

  test('tolerates missing optional fields', () async {
    final order = _fixtureOrder()
      ..remove('cashier_name')
      ..['items'] = [];
    final bytes = await InvoicePdfService().render(order);
    expect(bytes, isNotEmpty);
  });
}
