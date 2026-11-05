import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

final _service = PaymentService();

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
/// Acknowledgement is immediate and the work happens afterwards. A gateway that
/// does not get a 2xx retries — CutLuy eight times with backoff — so a slow
/// database or a hung bank call must not turn one delivery into eight.
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
  final pointer = _service.readNotification(
    rawBody: rawBody,
    headers: context.request.headers,
  );

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

  unawaited(_settle(pointer.tranId));
  return jsonSuccess(
    {'tran_id': pointer.tranId},
    statusCode: 202,
    message: 'Going to check ${pointer.tranId} with the gateway.',
  );
}

/// Ask the gateway what became of a payment, off the request's critical path.
///
/// Nothing here can be answered to the sender: the delivery only said something
/// changed. Failures are logged because a confirmation that did not happen is
/// invisible otherwise — the cashier's own poll still closes the sale, and the
/// gateway re-sends if this call ever reaches it again.
Future<void> _settle(String tranId) async {
  try {
    final payment = await _service.refresh(tranId);
    stderr.writeln('Notification settled $tranId as ${payment.status.name}');
  } catch (error, stackTrace) {
    stderr.writeln('Could not settle $tranId: $error\n$stackTrace');
  }
}
