import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context) async {
  final users = await const UserService().allRefs();
  return jsonSuccess([for (final user in users) user.toRefJson()]);
}
