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
  final raw = body['is_active'] ?? body['status'];
  if (raw == null) {
    throw InvalidEntityException(['is_active is required']);
  }
  final isActive =
      raw == true || raw == 1 || raw == '1' || raw.toString().toLowerCase() == 'true';
  await const UserService().setActive(id, isActive);
  final user = await const UserService().get(id);
  return jsonSuccess(user.toJson(), message: 'User status has been updated.');
}
