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
  final result = await const UserService().list(
    page: query.page,
    limit: query.limit,
    key: query.key,
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
  final phone = validator.requireString(body, 'phone');
  final email = validator.requireString(body, 'email');
  final password = validator.requireString(body, 'password');
  final roleIds = _roleIds(body, validator);
  validator.throwIfInvalid();

  final user = await const UserService().create(
    name: name,
    phone: phone,
    email: email,
    password: password,
    roleIds: roleIds,
  );
  return jsonSuccess(
    user.toJson(),
    statusCode: 201,
    message: 'User has been created.',
  );
}

List<int> _roleIds(Map<String, dynamic> body, Validator validator) {
  final raw = body['roles'] ?? body['role'];
  if (raw == null) {
    validator.errors.add('roles is required');
    return const [];
  }
  final values = raw is List ? raw : [raw];
  final ids = <int>[];
  for (final value in values) {
    final id = value is num ? value.toInt() : int.tryParse('$value');
    if (id == null) {
      validator.errors.add('roles must be role ids (numbers)');
      return const [];
    }
    ids.add(id);
  }
  return ids;
}
