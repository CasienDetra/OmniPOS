import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = PaymentService();

/// Transactions being settled right now.
final _inFlight = <String>{};

/// The gateway's "this payment changed state" call.
///
/// This is the only route in the API that answers without a token and cannot
/// have one: it is called by a payments company, not by our own client. That
/// makes it the least trusted entry point in the system, so two rules hold.
/// The body is verified as the bytes that arrived — CutLuy signs, and a
/// signature computed over re-serialised JSON never matches — and what the
/// delivery claims about money is never believed: it is a pointer to a
/// transaction, and the transaction is looked up again through the
/// authenticated API before a Sale is written.
///
/// The settlement is awaited before the acknowledgement. A gateway that does
/// not get a 2xx retries — CutLuy eight times with backoff — so a database or
/// bank call that failed is retried by the only party that still has the
/// delivery, instead of being acknowledged and lost.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _post(RequestContext context) async {
  // Read as text and re-encode, rather than reading the byte stream: dart_frog
  // can only read a body once, and the same content has to be both signature
  // input and JSON source. Valid UTF-8 round-trips exactly, which is what the
  // sender hashed.
  final rawBody = utf8.encode(await context.request.body());
  final headers = context.request.headers;
  final pointer = _service.readNotification(rawBody: rawBody, headers: headers);

  final payment = await _service.find(pointer.tranId);
  if (payment == null) {
    // Authenticated, and about a transaction this service never issued: the
    // gateway's endpoint belongs to another deployment. Loud in the log, quiet
    // on the wire — refusing it would buy eight retries of a message that can
    // never become ours.
    stderr.writeln(
      'Payment notification for unknown transaction ${pointer.tranId}',
    );
    return jsonSuccess(null, message: 'Noted.');
  }

  // Already settled. Replaying a paid callback must not become an unlimited
  // read of the gateway's API.
  if (payment.status.isTerminal) {
    return jsonSuccess({
      'tran_id': pointer.tranId,
      'status': payment.status.name,
    }, message: 'Already ${payment.status.name}.');
  }

  // The first parse had to guess which gateway sent this; now that the payment
  // is known, its own provider verifies the delivery before anything is asked
  // about the money.
  final verified = _service.verifyNotification(
    payment,
    rawBody: rawBody,
    headers: headers,
  );
  if (verified.tranId != pointer.tranId) {
    throw const BadRequestException('The notification names two transactions');
  }

  // Only one settlement per transaction at a time. The delivery already
  // running may describe an older event than this one — a pending answer for a
  // payment that has just been paid — so this one is not acknowledged: its
  // retry asks the gateway again once the settlement ahead has finished.
  if (!_inFlight.add(pointer.tranId)) {
    throw const ServiceUnavailableException(
      'Another notification for this transaction is being settled; retry it.',
    );
  }

  try {
    final settled = await _service.refresh(pointer.tranId);
    stderr.writeln(
      'Notification settled ${pointer.tranId} as ${settled.status.name}',
    );
    return jsonSuccess({
      'tran_id': pointer.tranId,
      'status': settled.status.name,
    }, message: 'Settled as ${settled.status.name}.');
  } catch (error, stackTrace) {
    // The sender is not told this delivery was handled: its retry is what
    // turns a database or network failure into the Sale it should have been.
    stderr.writeln('Could not settle ${pointer.tranId}: $error\n$stackTrace');
    throw const ServiceUnavailableException(
      'The notification could not be settled; retry it.',
    );
  } finally {
    _inFlight.remove(pointer.tranId);
  }
}
