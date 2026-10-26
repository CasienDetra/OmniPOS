import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _post(RequestContext context) async {
  final body = await jsonBody(context);
  final validator = Validator();
  final roleId = validator.requireInt(body, 'role_id');
  validator.throwIfInvalid();

  final user = await const AuthService().switchRole(authUser(context), roleId);
  const tokens = TokenService();
  return jsonSuccess({
    'token': tokens.generate(user),
  }, message: 'Role switched successfully');
}
