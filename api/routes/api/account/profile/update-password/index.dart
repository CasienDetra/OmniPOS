import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.put => await _put(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _put(RequestContext context) async {
  final auth = authUser(context);
  final body = await jsonBody(context);
  final validator = Validator();
  final oldPassword = validator.requireString(body, 'old_password');
  final newPassword = validator.requireString(body, 'new_password');
  validator.throwIfInvalid();

  await const UserService().changePassword(
    asObjectId(auth.id),
    oldPassword,
    newPassword,
  );
  return jsonSuccess(null, message: 'Password updated successfully');
}
