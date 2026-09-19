import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, id),
    HttpMethod.delete => await _delete(context, id),
    _ => Response(statusCode: 405),
  };
}

final _service = OrderService();

Future<Response> _get(RequestContext context, String id) async {
  final auth = authUser(context);
  final order =
      await _service.getFor(rawId: id, cashier: asObjectId(auth.id));
  return jsonSuccess(order.toJson(cashierName: auth.name));
}

Future<Response> _delete(RequestContext context, String id) async {
  final auth = authUser(context);
  await _service.getFor(rawId: id, cashier: asObjectId(auth.id));
  await _service.delete(id);
  return jsonSuccess(null, message: 'Sale has been deleted.');
}
