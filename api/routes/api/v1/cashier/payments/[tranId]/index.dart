import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = PaymentService();

/// One payment, addressed by the transaction id the gateway was given.
///
/// Reading it asks the gateway what became of the code, which is what a
/// counter screen does every few seconds while the customer fumbles with their
/// phone.
/// Once the answer is `paid` the Sale exists, and `sale_id` and
/// `receipt_number` come back with it.
Future<Response> onRequest(RequestContext context, String tranId) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, tranId),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context, String tranId) async {
  final auth = authUser(context);
  final payment = await _service.refresh(
    tranId,
    cashier: asObjectId(auth.id),
  );
  return jsonSuccess(payment.toJson(cashierName: auth.name));
}
