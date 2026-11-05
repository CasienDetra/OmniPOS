import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = PaymentService();

/// The code as an image, drawn from the payload this service already holds.
///
/// A counter refreshes this far more often than it needs the gateway's answer,
/// so the route reads the stored payment and never calls out — the status
/// endpoints do that. Error correction is level H, which is what lets a till
/// put a logo over the centre of the code without breaking the scan.
///
/// The customer never leaves this screen: there is no `checkout_url` in the
/// chain, only the KHQR payload the banking app reads.
Future<Response> onRequest(RequestContext context, String tranId) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, tranId),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _get(RequestContext context, String tranId) async {
  final auth = authUser(context);
  final payment = await _service.get(tranId);
  if (payment.cashierId != asObjectId(auth.id)) {
    throw const ForbiddenException('This payment belongs to another cashier');
  }
  if (payment.status != PaymentStatus.pending || payment.qrString.isEmpty) {
    // A paid or expired code must stop being shown, not keep scanning.
    throw GoneException(
      'Payment "$tranId" is ${payment.status.name}, so its code is no longer '
      'displayable',
    );
  }
  return Response(
    statusCode: 200,
    headers: {
      ...corsHeaders,
      'content-type': 'image/svg+xml; charset=utf-8',
      // The same URL changes meaning the moment the customer pays, and a
      // cached code is a code that outlives its own sale.
      'cache-control': 'no-store',
    },
    body: qrSvg(payment.qrString),
  );
}
