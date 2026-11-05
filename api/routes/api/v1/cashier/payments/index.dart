import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = PaymentService();

/// Open a QR payment for a cart: `{cart, platform}`, the same cart the cash
/// checkout takes.
///
/// Nothing is sold and no receipt number is drawn by this call. It answers with
/// the code to put on the counter screen; the Sale appears only when the
/// gateway confirms the code was paid. Which gateway — CutLuy or PayWay — is
/// `PAYMENT_PROVIDER`, and this route does not know or care.
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
  final payment = await _service.createPayment(
    cart: cart,
    platform: platform,
    cashierId: asObjectId(auth.id),
  );
  return jsonSuccess(
    payment.toJson(cashierName: auth.name),
    statusCode: 201,
    message:
        'QR payment created. Display it and poll until the status is '
        'paid, expired, or declined.',
  );
}
