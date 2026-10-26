import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context) async {
  final query = listQuery(context);
  final result = await const ProductTypeService().list(
    page: query.page,
    limit: query.limit,
  );
  return jsonSuccess(
    result['data'],
    pagination: result['pagination'] as Map<String, Object?>,
  );
}

Future<Response> _post(RequestContext context) async {
  requireRole(context, Role.admin);
  final body = await jsonBody(context);
  final validator = Validator();
  final name = validator.requireString(body, 'name');
  validator.throwIfInvalid();

  final type = await const ProductTypeService().create(name);
  return jsonSuccess(
    type.toJson(),
    statusCode: 201,
    message: 'Product type has been created.',
  );
}
