import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

/// Serves the OpenAPI 3.0.3 document backing the /swagger UI.
Response onRequest(RequestContext context) {
  return Response(
    body: openApiSpecJson,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}
