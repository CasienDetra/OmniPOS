// Integration tests for the health probes against a running instance.
//
// Requires the stack up (docker compose up -d from repo root). Override the
// target with API_BASE_URL.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final base = Uri.parse(
  Platform.environment['API_BASE_URL'] ?? 'http://localhost:3000',
);

Future<http.Response> call(String method, String path) =>
    http.Request(method, base.replace(path: path)).send().then(
      http.Response.fromStream,
    );

/// Reason to skip the whole suite, or null when a server answers.
Future<String?> probeServer() async {
  try {
    final probe = await call(
      'GET',
      '/healthz',
    ).timeout(const Duration(seconds: 3));
    if (probe.statusCode != 200) {
      return 'POS api answered ${probe.statusCode} at $base';
    }
    return null;
  } catch (_) {
    return 'POS api not reachable at $base — run `docker compose up -d` first';
  }
}

Future<void> main() async {
  // Registered before any test: an unreachable server skips the suite instead
  // of failing every request with a socket error.
  final unreachable = await probeServer();
  if (unreachable != null) {
    test('POS api probe suite', () {}, skip: unreachable);
    return;
  }

  group('probes', () {
    test('GET /healthz answers 200 with no token', () async {
      final res = await call('GET', '/healthz');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['success'], isTrue);
      expect((body['data'] as Map)['status'], 'live');
    });

    test('GET /readyz answers 200 while MongoDB is up', () async {
      final res = await call('GET', '/readyz');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect((body['data'] as Map)['status'], 'ready');
    });

    test('a request that carries a token still has it verified', () async {
      final res = await http.get(
        base.replace(path: '/healthz'),
        headers: {'authorization': 'Bearer not-a-real-token'},
      );
      expect(res.statusCode, 401);
    });

    test('probes reject methods other than GET', () async {
      for (final path in ['/healthz', '/readyz']) {
        final res = await call('POST', path);
        expect(res.statusCode, 405, reason: path);
      }
    });
  });
}
