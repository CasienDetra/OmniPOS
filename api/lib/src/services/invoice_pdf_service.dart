import 'dart:typed_data';

import 'package:khmer_pdf_shaper/khmer_pdf_shaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoicePdfService {
  InvoicePdfService();

  static const _headerBlue = PdfColor.fromInt(0xFF6E92F5);
  static const _linkBlue = PdfColor.fromInt(0xFF0000FF);
  static const _green = PdfColor.fromInt(0xFF008000);
  static const _line = PdfColor.fromInt(0xFFD3D3D3);

  /// Renders one order (in the shape of `Order.toJson`) as an A4 invoice,
  /// replicating the handlebars layout of jsreport's `invoice-pos` template.
  Future<Uint8List> render(Map<String, Object?> order) async {
    final base = pw.TextStyle(fontSize: 11);
    final items = (order['items'] as List? ?? const [])
        .map((item) => Map<String, Object?>.from(item as Map))
        .toList();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageTheme: const pw.PageTheme(pageFormat: PdfPageFormat.a4),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _topHeader(base, order),
            _divider(),
            _secondHeader(base, order),
            pw.SizedBox(height: 8),
            _itemsTable(base, items, order),
            _divider(),
          ],
        ),
      ),
    );
    return (await doc.save()).buffer.asUint8List();
  }

  pw.Widget _topHeader(pw.TextStyle base, Map<String, Object?> order) {
    final style = base.copyWith(fontSize: 16);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          KhmerText('លេខវិក្ក័យបត្រ ', style: style),
          KhmerText(
            '#${order['receipt_number']}',
            style: style.copyWith(color: _linkBlue),
          ),
        ],
      ),
    );
  }

  pw.Widget _secondHeader(pw.TextStyle base, Map<String, Object?> order) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: KhmerText(
              'បង្កើតនៅៈ ${_formatDate(order['ordered_at'])}',
              style: base,
            ),
          ),
          pw.Expanded(
            child: KhmerText(
              'អ្នកគិតលុយៈ ${order['cashier_name'] ?? ''}',
              style: base,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _itemsTable(
    pw.TextStyle base,
    List<Map<String, Object?>> items,
    Map<String, Object?> order,
  ) {
    final header = ['ឈ.រ', 'ផលិតផល', 'តម្លៃ (រៀល)', 'ចំនួន', 'សរុប'];
    final cell = pw.EdgeInsets.all(5);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _line)),
      ),
      child: pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(0.6),
          1: pw.FlexColumnWidth(3),
          2: pw.FlexColumnWidth(1.6),
          3: pw.FlexColumnWidth(1),
          4: pw.FlexColumnWidth(1.4),
        },
        children: [
          pw.TableRow(
            children: [
              for (final title in header)
                pw.Container(
                  padding: cell,
                  color: _headerBlue,
                  child: KhmerText(title, style: base),
                ),
            ],
          ),
          for (var i = 0; i < items.length; i++)
            pw.TableRow(
              children: [
                pw.Padding(
                  padding: cell,
                  child: KhmerText('${i + 1}', style: base),
                ),
                pw.Padding(
                  padding: cell,
                  child: KhmerText('${items[i]['name']}', style: base),
                ),
                pw.Padding(
                  padding: cell,
                  child: KhmerText(_money(items[i]['unit_price']), style: base),
                ),
                pw.Padding(
                  padding: cell,
                  child: KhmerText('${items[i]['qty']}', style: base),
                ),
                pw.Padding(
                  padding: cell,
                  child: KhmerText(_money(items[i]['line_price']), style: base),
                ),
              ],
            ),
          pw.TableRow(
            children: [
              pw.SizedBox(),
              pw.Container(
                padding: cell,
                child: KhmerText(
                  'តម្លៃសរុប (រៀល):',
                  style: base,
                  textAlign: pw.TextAlign.right,
                ),
              ),
              pw.SizedBox(),
              pw.SizedBox(),
              pw.Padding(
                padding: cell,
                child: KhmerText(
                  _money(order['total_price']),
                  style: base.copyWith(
                    font: pw.Font.helveticaBold(),
                    color: _green,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _divider() => pw.Container(
    height: 1,
    color: _line,
    margin: const pw.EdgeInsets.symmetric(vertical: 2),
  );

  String _formatDate(Object? iso) {
    if (iso is! String || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  String _money(Object? value) {
    final n = value is num ? value : num.tryParse('$value') ?? 0;
    return n == n.round() ? n.toInt().toString() : n.toStringAsFixed(2);
  }
}
