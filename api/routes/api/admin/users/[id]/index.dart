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
  final user = await const UserService().get(id);
  return jsonSuccess(user.toJson());
}

Future<Response> _put(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  final body = await jsonBody(context);
  final validator = Validator();
  final name = validator.optionalString(body, 'name');
  final phone = validator.optionalString(body, 'phone');
  final email = validator.optionalString(body, 'email');
  List<int>? roleIds;
  if (body['roles'] != null || body['role'] != null) {
    roleIds = _roleIds(body, validator);
  }
  validator.throwIfInvalid();

  await const UserService().update(
    id,
    name: name,
    phone: phone,
    email: email,
    roleIds: roleIds,
  );
  final user = await const UserService().get(id);
  return jsonSuccess(user.toJson(), message: 'User has been updated.');
}

Future<Response> _delete(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  await const UserService().delete(id);
  return jsonSuccess(null, message: 'User has been deleted.');
}

List<int> _roleIds(Map<String, dynamic> body, Validator validator) {
  final raw = body['roles'] ?? body['role'];
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
