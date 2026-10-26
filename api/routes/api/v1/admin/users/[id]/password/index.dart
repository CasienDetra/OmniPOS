import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.put => await _put(context, id),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _put(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  final body = await jsonBody(context);
  final validator = Validator();
  final password = validator.requireString(body, 'password');
  validator.throwIfInvalid();

  await const UserService().resetPassword(id, password);
  return jsonSuccess(null, message: 'Password has been updated.');
}
