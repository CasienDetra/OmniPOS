// Guards the URL space against drift: the route tree, the auth guard's
// version prefix and the OpenAPI document are three separate descriptions of
// the same paths, and only the first two are load-bearing. A rename that
// updates one and not the others would otherwise ship either an undocumented
// API or a guard that never matches.
import 'dart:convert';
import 'dart:io';

import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// Routes are file-based: `routes/<segments>/index.dart` answers
/// `/<segments>`, with a `[name]` directory becoming the `{name}` template
/// the OpenAPI document uses.
List<String> routePathsOnDisk() {
  final root = Directory('routes/api');
  if (!root.existsSync()) {
    throw StateError(
      'routes/api is missing from ${Directory.current.path}; unit tests must '
      'run from the api package root',
    );
  }
  final paths = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    final fileName = entity.uri.pathSegments.last;
    if (entity is! File || fileName != 'index.dart') {
      continue;
    }
    final segments = entity.parent.path
        .replaceFirst('routes/', '')
        .split('/')
        .map((segment) {
          if (!segment.startsWith('[') || !segment.endsWith(']')) {
            return segment;
          }
          return '{${segment.substring(1, segment.length - 1)}}';
        })
        .join('/');
    paths.add('/$segments');
  }
  return paths..sort();
}

Map<String, dynamic> get specPaths {
  final document = jsonDecode(openApiSpecJson) as Map<String, dynamic>;
  return document['paths'] as Map<String, dynamic>;
}

void main() {
  group('api routes', () {
    test('every versioned route lives under the declared apiPrefix', () {
      for (final path in routePathsOnDisk()) {
        expect(path, startsWith('$apiPrefix/'), reason: path);
      }
    });

    test('the guard sections name directories that actually exist', () {
      // If adminPrefix stopped matching real routes, the Admin check would
      // protect nothing and no other test would notice.
      final onDisk = routePathsOnDisk();
      expect(
        onDisk.where((path) => path.startsWith('$adminPrefix/')),
        isNotEmpty,
        reason: adminPrefix,
      );
      expect(
        onDisk.where((path) => path.startsWith('$cashierPrefix/')),
        isNotEmpty,
        reason: cashierPrefix,
      );
    });

    test('the public prefixes match real login and testing routes', () {
      final onDisk = routePathsOnDisk();
      expect(onDisk, contains(loginPath));
      expect(
        onDisk.where((path) => path.startsWith('$testingPrefix/')),
        isNotEmpty,
        reason: testingPrefix,
      );
    });

    test('the OpenAPI document lists exactly the routes on disk', () {
      final documented = specPaths.keys
          .where((path) => path.startsWith('$apiPrefix/'))
          .toSet();
      final onDisk = routePathsOnDisk().toSet();
      expect(
        onDisk.difference(documented),
        isEmpty,
        reason: 'routes missing from the OpenAPI document',
      );
      expect(
        documented.difference(onDisk),
        isEmpty,
        reason: 'OpenAPI paths with no route behind them',
      );
    });
  });
}
