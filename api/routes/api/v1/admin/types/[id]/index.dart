import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, id),
    HttpMethod.put => await _put(context, id),
    HttpMethod.delete => await _delete(context, id),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context, String id) async {
  return jsonSuccess(
    await const ProductTypeService().get(id).then((t) => t.toJson()),
  );
}

Future<Response> _put(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  final body = await jsonBody(context);
  final validator = Validator();
  final name = validator.requireString(body, 'name');
  validator.throwIfInvalid();

  await const ProductTypeService().update(id, name);
  return jsonSuccess(null, message: 'Product type has been updated.');
}

Future<Response> _delete(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  await const ProductTypeService().delete(id);
  return jsonSuccess(null, message: 'Product type has been deleted.');
}
