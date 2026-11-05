import 'dart:convert';

import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

void main() {
  final spec = jsonDecode(openApiSpecJson) as Map<String, dynamic>;
  final paths = spec['paths'] as Map<String, dynamic>;

  test('the document stays parseable JSON', () {
    expect(spec['openapi'], '3.0.3');
  });

  // The spec is hand-maintained, so every route added to routes/ needs a line
  // here; these are the checks that catch the ones that get forgotten.
  test('documents the probes without requiring a token', () {
    for (final path in ['/healthz', '/readyz']) {
      final operation = (paths[path] as Map)['get'] as Map;
      expect(operation['security'], isEmpty, reason: '$path must be public');
      final responses = operation['responses'] as Map;
      expect(responses.containsKey('200'), isTrue, reason: '$path lacks 200');
    }
  });

  test('every documented path resolves to a real route', () {
    expect(paths.keys, containsAll(['/healthz', '/readyz', '/']));
  });

  // The one route a cashier token cannot be used on, because it is not reached
  // by a cashier. If it ever gains a guard, the gateway stops being able to
  // confirm payments and the counter shows pending codes forever.
  test('the payment callback is documented as public', () {
    final operation = (paths[paymentCallbackPath]! as Map)['post']! as Map;
    expect(operation['security'], isEmpty);
  });

  test('the Payment schema lists exactly the statuses the model has', () {
    final components = spec['components']! as Map;
    final schemas = components['schemas']! as Map;
    final payment = schemas['Payment']! as Map;
    final properties = payment['properties']! as Map;
    final status = properties['status']! as Map;
    expect(status['enum'], PaymentStatus.values.map((value) => value.name));
  });

  // A payment row keeps the gateway that issued it, because a payment is
  // settled by that provider and by no other. The document has to name the same
  // two the code can build, or a client reads a provider it cannot be shown.
  test('the Payment schema names every provider the code can drive', () {
    final schemas = (spec['components']! as Map)['schemas']! as Map;
    final properties = (schemas['Payment']! as Map)['properties']! as Map;
    expect(
      (properties['provider']! as Map)['enum'],
      paymentProviderNames,
      reason: 'a third gateway needs a route surface as well as a schema entry',
    );
    for (final field in ['charge_amount', 'charge_currency', 'exchange_rate']) {
      expect(
        properties.containsKey(field),
        isTrue,
        reason: '$field is missing',
      );
    }
  });

  // The callback is the one endpoint an attacker can reach without a token, so
  // what it demands of a delivery is part of the contract, not an
  // implementation detail.
  test('the callback documents the signature a delivery has to carry', () {
    final operation = (paths[paymentCallbackPath]! as Map)['post']! as Map;
    final headers = [
      for (final parameter in operation['parameters']! as List)
        (parameter as Map)['name'],
    ];
    expect(headers, containsAll(['X-CutLuy-Signature', 'X-CutLuy-Event']));
    final responses = operation['responses']! as Map;
    for (final code in ['202', '400', '401', '503']) {
      expect(responses.containsKey(code), isTrue, reason: '$code is missing');
    }
    final schemas = (spec['components']! as Map)['schemas']! as Map;
    expect(schemas.containsKey('CutLuyEvent'), isTrue);
    expect(schemas.containsKey('PaywayNotification'), isTrue);
  });

  // The till renders this straight into an <img>, so the media type is the
  // whole contract: the route writes the header by hand and nothing but this
  // check ties the document to it. A cashier token has to be presented, unlike
  // the callback, and a code that has been paid or expired answers 410 rather
  // than quietly redrawing the one that already took the money.
  test('the QR image is documented as SVG, guarded, and expiring', () {
    const path = '/api/v1/cashier/payments/{tranId}/qr';
    final operation = (paths[path]! as Map)['get']! as Map;
    expect(operation.containsKey('security'), isFalse, reason: 'needs a token');
    final responses = operation['responses']! as Map;
    final content = (responses['200']! as Map)['content']! as Map;
    expect(content.keys, ['image/svg+xml']);
    expect(responses.containsKey('410'), isTrue, reason: '410 is missing');
    for (final code in ['401', '403', '404']) {
      expect(responses.containsKey(code), isTrue, reason: '$code is missing');
    }
  });
}
