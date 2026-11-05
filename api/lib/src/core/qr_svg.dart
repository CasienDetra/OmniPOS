/// A KHQR payload drawn as an SVG image, so a counter can show a code without
/// ever sending a customer to a gateway-hosted page.
///
/// The payload only ever selects modules — it is never written into the
/// markup — so nothing a gateway puts in a QR can escape into a client's DOM.
library;

import 'package:qr/qr.dart';

/// The modules of [payload] as a square grid, `true` for dark, with a white
/// quiet zone of [quietZone] modules painted around it.
///
/// Error correction is level **H**, the only level that survives a logo or a
/// riel medallion laid over the centre of the code, which is where a till
/// screen wants one. It costs a larger symbol for the same text; that is the
/// trade the specification makes for us.
List<List<bool>> qrModuleRows(String payload, {int quietZone = 4}) {
  if (payload.isEmpty) {
    throw ArgumentError.value(payload, 'payload', 'cannot be empty');
  }
  if (quietZone < 0) {
    throw ArgumentError.value(quietZone, 'quietZone', 'cannot be negative');
  }
  final image = QrImage(
    QrCode.fromData(data: payload, errorCorrectLevel: QrErrorCorrectLevel.H),
  );
  final size = image.moduleCount + quietZone * 2;
  return List.generate(size, (row) {
    final codeRow = row - quietZone;
    return List.generate(size, (col) {
      final codeCol = col - quietZone;
      if (codeRow < 0 ||
          codeCol < 0 ||
          codeRow >= image.moduleCount ||
          codeCol >= image.moduleCount) {
        return false;
      }
      return image.isDark(codeRow, codeCol);
    });
  });
}

/// [qrModuleRows] as a standalone SVG: one `<rect>` per run of dark modules in
/// a row, which keeps the file small enough to send to a till on every redraw.
String qrSvg(String payload, {int moduleSize = 4, int quietZone = 4}) {
  if (moduleSize < 1) {
    throw ArgumentError.value(moduleSize, 'moduleSize', 'must be at least 1');
  }
  final rows = qrModuleRows(payload, quietZone: quietZone);
  final size = rows.length * moduleSize;
  final opening =
      '<svg xmlns="http://www.w3.org/2000/svg" width="$size" height="$size" '
      'viewBox="0 0 $size $size" shape-rendering="crispEdges">';
  final parts = <String>[
    opening,
    '<rect width="$size" height="$size" fill="#ffffff"/>',
  ];
  for (var row = 0; row < rows.length; row++) {
    final line = rows[row];
    var run = -1;
    for (var col = 0; col <= line.length; col++) {
      final dark = col < line.length && line[col];
      if (dark && run < 0) {
        run = col;
      } else if (!dark && run >= 0) {
        parts.add(
          '<rect x="${run * moduleSize}" y="${row * moduleSize}" '
          'width="${(col - run) * moduleSize}" height="$moduleSize"/>',
        );
        run = -1;
      }
    }
  }
  parts.add('</svg>');
  return parts.join();
}
