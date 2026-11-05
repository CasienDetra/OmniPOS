import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// A real KHQR payload, taken from CutLuy's own documented example payment,
/// percent-decoded. The numbers pinned below are the symbol it produces; a
/// renderer that quietly changed its mask, its version choice, or its module
/// order would keep drawing plausible-looking squares and fail only in front of
/// a bank's scanner, so they are asserted here instead.
const String _demoPayload =
    '00020101021229330016cutluy_demo@bkrt010900000000052045999530384054041'
    '.505802KH5911CutLuy Demo6010Phnom Penh62140110order_102463045F4B';

/// The same payload as a grid with the default quiet zone: 61 modules of code
/// plus four white on each side.
const int _demoGrid = 69;
const int _demoDarkModules = 1890;

/// Reads [rows] as a square grid of booleans, `#` for dark.
String _row(List<bool> rows, int start, int length) =>
    rows.skip(start).take(length).map((dark) => dark ? '#' : '.').join();

bool _isAllWhite(List<bool> line) => line.every((dark) => !dark);

void main() {
  group('qrModuleRows', () {
    test('paints the documented payload as a known grid', () {
      final rows = qrModuleRows(_demoPayload);
      expect(rows, hasLength(_demoGrid));
      expect(rows.every((row) => row.length == _demoGrid), isTrue);
      expect(
        rows.fold<int>(0, (sum, row) => sum + row.where((d) => d).length),
        _demoDarkModules,
      );
    });

    test('keeps the quiet zone white on all four sides', () {
      final rows = qrModuleRows(_demoPayload, quietZone: 4);
      for (final edge in [rows[0], rows[1], rows[3], rows[_demoGrid - 1]]) {
        expect(_isAllWhite(edge), isTrue, reason: 'top and bottom margins');
      }
      expect(rows.every((row) => !row[0] && !row[3]), isTrue);
      expect(
        rows.every(
          (row) => !row[_demoGrid - 1] && !row[_demoGrid - 4],
        ),
        isTrue,
      );
    });

    test('a quiet zone of zero starts at the code itself', () {
      final rows = qrModuleRows(_demoPayload, quietZone: 0);
      expect(rows, hasLength(_demoGrid - 8));
      expect(_row(rows[0], 0, 7), '#######');
    });

    test('draws the three finder patterns a scanner looks for', () {
      final rows = qrModuleRows(_demoPayload, quietZone: 0);
      const finder = [
        '#######',
        '#.....#',
        '#.###.#',
        '#.###.#',
        '#.###.#',
        '#.....#',
        '#######',
      ];
      for (var i = 0; i < 7; i++) {
        expect(_row(rows[i], 0, 7), finder[i], reason: 'top-left row $i');
        expect(
          _row(rows[i], rows.length - 7, 7),
          finder[i],
          reason: 'top-right row $i',
        );
        expect(
          _row(rows[rows.length - 7 + i], 0, 7),
          finder[i],
          reason: 'bottom-left row $i',
        );
      }
    });

    test('a longer payload needs a bigger symbol at the same margin', () {
      expect(qrModuleRows('00020101021229', quietZone: 0), hasLength(25));
      expect(qrModuleRows(_demoPayload, quietZone: 0), hasLength(61));
    });

    test('is deterministic', () {
      expect(qrModuleRows(_demoPayload), qrModuleRows(_demoPayload));
    });

    test('refuses to encode nothing, or with a negative margin', () {
      expect(() => qrModuleRows(''), throwsArgumentError);
      expect(
        () => qrModuleRows(_demoPayload, quietZone: -1),
        throwsArgumentError,
      );
    });
  });

  group('qrSvg', () {
    test('is a standalone square image sized in modules', () {
      final svg = qrSvg(_demoPayload);
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('width="${_demoGrid * 4}"'));
      expect(svg, contains('viewBox="0 0 ${_demoGrid * 4} ${_demoGrid * 4}"'));
      expect(svg, endsWith('</svg>'));
    });

    test('scales by the module size alone', () {
      final small = qrSvg(_demoPayload, moduleSize: 4);
      final large = qrSvg(_demoPayload, moduleSize: 8);
      expect(large, contains('width="${_demoGrid * 8}"'));
      expect(
        '<rect'.allMatches(large).length,
        '<rect'.allMatches(small).length,
        reason: 'the same runs, twice as wide',
      );
    });

    test('one rect per run of dark modules, plus the white ground', () {
      final rows = qrModuleRows(_demoPayload);
      final runs = rows.fold<int>(
        0,
        (sum, row) => sum + _runCount(row),
      );
      expect('<rect'.allMatches(qrSvg(_demoPayload)).length, runs + 1);
    });

    test('never writes the payload into the markup', () {
      final svg = qrSvg(_demoPayload);
      expect(svg, isNot(contains('cutluy_demo')));
      expect(svg, isNot(contains('order_1024')));
      // A payload is untrusted text from a gateway; it must not be able to
      // become an element, a comment, or a CDATA section.
      const hostile = '</svg><script>alert(1)</script>]]>$_demoPayload';
      final hostileSvg = qrSvg(hostile);
      expect(hostileSvg, isNot(contains('<script')));
      expect(hostileSvg, isNot(contains(']]>')));
      expect('<svg'.allMatches(hostileSvg).length, 1);
    });

    test('refuses a module size that would collapse the image', () {
      expect(() => qrSvg(_demoPayload, moduleSize: 0), throwsArgumentError);
    });
  });
}

int _runCount(List<bool> row) {
  var runs = 0;
  for (var i = 0; i < row.length; i++) {
    if (row[i] && (i == 0 || !row[i - 1])) runs++;
  }
  return runs;
}
