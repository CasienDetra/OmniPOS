import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, id),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context, String id) async {
  final auth = authUser(context);
  final orders = OrderService();
  final Map<String, Object?> order;
  if (auth.hasRole(Role.admin)) {
    order = await orders.getJson(id);
  } else {
    order = (await orders.getFor(rawId: id, cashier: asObjectId(auth.id)))
        .toJson(cashierName: auth.name);
  }
  final bytes = await InvoicePdfService().render(order);
  return Response.bytes(
    body: bytes,
    headers: {
      'content-type': 'application/pdf',
      'content-disposition':
          'inline; filename="invoice-${order['receipt_number']}.pdf"',
    },
  );
}
