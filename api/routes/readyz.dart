import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

/// Readiness: answers 200 only when the database ping succeeds, so a restart
/// stops routing traffic to a service that cannot serve orders.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _ready(),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _ready() async {
  await MongoDb.instance.database;
  return jsonSuccess({'status': 'ready'});
}
