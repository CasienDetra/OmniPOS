import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = OrderService();

/// Checkout: body `{cart, platform}` where cart is either a JSON string
/// `'{"<productId>": <qty>}'` (v4 contract) or an equivalent object.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _post(RequestContext context) async {
  requireRole(context, Role.cashier);
  final auth = authUser(context);
  final body = await jsonBody(context);
  final validator = Validator();
  final platform = validator.optionalString(body, 'platform') ?? 'Web';
  final rawCart = body['cart'];
  if (rawCart == null) validator.errors.add('cart is required');
  validator.throwIfInvalid();

  final cart = rawCart is String ? rawCart : jsonEncode(rawCart);
  final order = await _service.createOrder(
    cart: cart,
    platform: platform,
    cashierId: asObjectId(auth.id),
  );
  return jsonSuccess(
    order.toJson(cashierName: auth.name),
    statusCode: 201,
    message: 'Order has been placed successfully.',
  );
}
