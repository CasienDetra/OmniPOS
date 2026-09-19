import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Response onRequest(RequestContext context) {
  return jsonSuccess({
    'service': 'pos-api',
    'status': 'ok',
    'time': DateTime.now().toUtc().toIso8601String(),
  });
}
