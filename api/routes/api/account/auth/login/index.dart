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
  final username = validator.requireString(body, 'username');
  final password = validator.requireString(body, 'password');
  final platform = validator.optionalString(body, 'platform') ?? 'Web';
  validator.throwIfInvalid();

  const service = AuthService();
  final user = await service.login(username: username, password: password);
  await service.recordLogin(
    user,
    DeviceInfo.fromHeaders(
      headers: context.request.headers,
      defaultPlatform: platform,
    ),
  );

  const tokens = TokenService();
  return jsonSuccess(
    {'token': tokens.generate(user)},
    message: 'Logged in successfully',
  );
}
