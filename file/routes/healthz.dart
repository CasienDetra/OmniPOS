import 'package:dart_frog/dart_frog.dart';
import 'package:pos_file/pos_file.dart';

/// Liveness only: proves the process serves without touching the database or
/// the upload directory, so a dependency outage never looks like a crashed
/// service.
Response onRequest(RequestContext context) {
  return switch (context.request.method) {
    HttpMethod.get => jsonSuccess({'status': 'live'}),
    _ => Response(statusCode: 405),
  };
}
