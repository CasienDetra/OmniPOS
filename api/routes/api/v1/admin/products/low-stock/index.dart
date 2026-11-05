import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = ProductService();

/// Products an admin has to restock: tracked products at or below their
/// warning line, and every tracked product with none left. Untracked products
/// never appear.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context) async {
  requireRole(context, Role.admin);
  final limit = queryInt(
    context.request.url.queryParameters,
    'limit',
    200,
    min: 1,
    max: 1000,
  );
  final result = await _service.lowStock(limit: limit);
  return jsonSuccess({
    'products': result['data'],
    'total': result['total'],
  });
}
