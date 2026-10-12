import 'dart:convert';

import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

void main() {
  final spec = jsonDecode(openApiSpecJson) as Map<String, dynamic>;
  final paths = spec['paths'] as Map<String, dynamic>;

  test('the document stays parseable JSON', () {
    expect(spec['openapi'], '3.0.3');
  });

  // The spec is hand-maintained, so every route added to routes/ needs a line
  // here; these are the checks that catch the ones that get forgotten.
  test('documents the probes without requiring a token', () {
    for (final path in ['/healthz', '/readyz']) {
      final operation = (paths[path] as Map)['get'] as Map;
      expect(operation['security'], isEmpty, reason: '$path must be public');
      final responses = operation['responses'] as Map;
      expect(responses.containsKey('200'), isTrue, reason: '$path lacks 200');
    }
  });

  test('every documented path resolves to a real route', () {
    expect(paths.keys, containsAll(['/healthz', '/readyz', '/']));
  });
}
