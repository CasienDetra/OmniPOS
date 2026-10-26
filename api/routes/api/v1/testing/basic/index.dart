import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    _ => Response(statusCode: 405),
  };
}

Response _get(RequestContext context) {
  return jsonSuccess({
    'method': context.request.method.name,
    'path': '/${context.request.url.path}',
    'query': context.request.url.queryParameters,
  }, message: 'Basic testing endpoint is working');
}
