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
  final name = validator.optionalString(body, 'name');
  final phone = validator.optionalString(body, 'phone');
  final email = validator.optionalString(body, 'email');
  final avatar = validator.optionalString(body, 'avatar');
  validator.throwIfInvalid();

  final id = asObjectId(auth.id);
  await const UserService()
      .updateProfile(id, name: name, phone: phone, email: email, avatar: avatar);
  final user = await const AuthService().loadUser(id);
  return jsonSuccess(user.toJson(), message: 'Profile updated successfully');
}
