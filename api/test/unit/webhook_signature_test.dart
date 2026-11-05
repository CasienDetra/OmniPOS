import 'dart:convert';

import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

/// Signed with `whsec_test_secret`. The digests are computed independently of
/// this code, with Python's `hmac` over the same `"<t>."` plus the raw bytes,
/// so a `webhookDigestHex` that stays self-consistent but stops matching what
/// CutLuy signs still fails here.
const String _secret = 'whsec_test_secret';

const String _eventBody =
    '{"id":"evt_2a","type":"payment.completed",'
    '"created":"2026-11-01T09:00:00.000Z","data":{"payment":'
    '{"id":"PUETcMUOKStjZsCb6zAl8kg9fMRGM85x","status":"paid",'
    '"amount":"3.66","currency":"USD","reference_id":"2603121000001",'
    '"metadata":null,"approved_at":"2026-11-01T09:02:11.000Z"}}}';

const String _digestAt1730000000 =
    '5668a8c01e9171787df5879f3bbe47e84df74070e6c17bfa36c5e0d4'
    'bc65b6a1';

/// Twenty-nine seconds inside the five-minute window.
const String _digestAt1730000299 =
    '8e16e75c60aa119e25db37f47dd58467a1c2f55758488c467aafb5b'
    'bef64acbb';

/// One second outside it.
const String _digestAt1730000301 =
    '0cf0204a326082466613ce2e7386279cab1f8ed4504a33ec007e937'
    'ca333959e';

/// Exactly on the boundary, on the far side of the clock.
const String _digestAt1729999700 =
    '7e8df2e5f573afaedb5209c54e8e68f2940e9d54d120b261856d906'
    '14eb41c52';

const String _digestAt1730000300 =
    'd0593426eb58581e1edef360e2c6c0e56ea6fbfc380fc064fda72d3'
    '4f1636d14';

const String _digestAt1729999699 =
    '5b3a980fc8edca1153c15a0e5a9d27f3949b10aa6e201e7b38500a2'
    '87f86aee8';

/// The digest of the same timestamp over a body whose amount was changed in
/// flight. Kept to show that the bytes a cashier is charged for and the bytes
/// that were signed are two different messages: the signature over the original
/// body says nothing about the edited one.
const String _digestOfTamperedBody =
    '17568e59b6b6feaefe9984ef0b7dba8b2c32d1bf9a432bdf9444a30'
    '7df191dee';

final DateTime _now = _at(1730000000);

DateTime _at(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

WebhookCheck _check({
  String? secret = _secret,
  String? header = 't=1730000000,v1=$_digestAt1730000000',
  List<int>? rawBody,
  DateTime? now,
  Duration tolerance = const Duration(minutes: 5),
}) => checkWebhookSignature(
  secret: secret,
  header: header,
  rawBody: rawBody ?? utf8.encode(_eventBody),
  now: now ?? _now,
  tolerance: tolerance,
);

void main() {
  group('webhookDigestHex', () {
    test('matches a digest computed outside this code', () {
      expect(
        webhookDigestHex(
          secret: _secret,
          rawBody: utf8.encode(_eventBody),
          timestamp: 1730000000,
        ),
        _digestAt1730000000,
      );
    });

    test('is sensitive to the timestamp alone', () {
      final raw = utf8.encode(_eventBody);
      expect(
        webhookDigestHex(secret: _secret, rawBody: raw, timestamp: 1730000299),
        _digestAt1730000299,
      );
      expect(
        webhookDigestHex(secret: _secret, rawBody: raw, timestamp: 1730000301),
        _digestAt1730000301,
      );
    });

    test('is sensitive to the secret', () {
      expect(
        webhookDigestHex(
          secret: 'whsec_other',
          rawBody: utf8.encode(_eventBody),
          timestamp: 1730000000,
        ),
        isNot(_digestAt1730000000),
      );
    });

    test('signs the small payload the same way', () {
      expect(
        webhookDigestHex(
          secret: _secret,
          rawBody: utf8.encode('{"type":"payment.completed"}'),
          timestamp: 1700000000,
        ),
        '0a409c41af8d7ee9316af1c3f756a8b44bc6bf72656a5a061c422e'
        '9bf7e507fd',
      );
    });
  });

  group('checkWebhookSignature', () {
    test('accepts a correctly signed, fresh delivery', () {
      expect(_check(), WebhookCheck.ok);
    });

    test('refuses a body edited after signing', () {
      final tampered = utf8.encode(
        _eventBody.replaceAll('"3.66"', '"36600.00"'),
      );
      // The delivered signature still says `payment.completed` for the right
      // transaction, and the timestamp is fresh. Only the bytes disagree.
      expect(_check(rawBody: tampered), WebhookCheck.signatureMismatch);
      expect(
        webhookDigestHex(
          secret: _secret,
          rawBody: tampered,
          timestamp: 1730000000,
        ),
        allOf(equals(_digestOfTamperedBody), isNot(_digestAt1730000000)),
      );
      expect(
        _check(
          header: 't=1730000000,v1=$_digestAt1730000000',
          rawBody: tampered,
        ),
        WebhookCheck.signatureMismatch,
      );
    });

    test('refuses a wrong secret', () {
      expect(_check(secret: 'whsec_not_ours'), WebhookCheck.signatureMismatch);
    });

    test('refuses a delivery with no header', () {
      expect(_check(header: null), WebhookCheck.headerMissing);
      expect(_check(header: ''), WebhookCheck.headerMissing);
    });

    test('refuses an absent secret instead of accepting unsigned bytes', () {
      expect(_check(secret: null), WebhookCheck.headerMissing);
      expect(_check(secret: ''), WebhookCheck.headerMissing);
    });

    test('refuses a header that is not t=…,v1=…', () {
      expect(
        _check(header: _digestAt1730000000),
        WebhookCheck.headerMalformed,
      );
      expect(
        _check(header: 't=1730000000'),
        WebhookCheck.headerMalformed,
      );
      expect(
        _check(header: 'v1=$_digestAt1730000000'),
        WebhookCheck.headerMalformed,
      );
      expect(
        _check(header: 't=not-a-number,v1=$_digestAt1730000000'),
        WebhookCheck.headerMalformed,
      );
    });

    test('reads the fields in any order and tolerates spacing', () {
      expect(
        _check(header: 'v1=$_digestAt1730000000, t=1730000000'),
        WebhookCheck.ok,
      );
    });

    test(
      'accepts a timestamp at the edge of the window and rejects past it',
      () {
        expect(
          _check(header: 't=1730000299,v1=$_digestAt1730000299'),
          WebhookCheck.ok,
        );
        expect(
          _check(header: 't=1730000301,v1=$_digestAt1730000301'),
          WebhookCheck.timestampStale,
        );
      },
    );

    test('measures the window in both directions', () {
      // A delivery from the future is as untrustworthy as an old one, and it
      // is refused before the digest is computed.
      expect(
        _check(header: 't=1730000301,v1=$_digestAt1730000301'),
        WebhookCheck.timestampStale,
      );
      expect(
        _check(
          header: 't=1730000300,v1=$_digestAt1730000300',
          now: _now,
        ),
        WebhookCheck.ok,
      );
    });

    test('an old delivery is stale even with a matching digest', () {
      expect(
        _check(header: 't=1729999699,v1=$_digestAt1729999699'),
        WebhookCheck.timestampStale,
      );
      // Exactly five minutes old is still the sender's own work.
      expect(
        _check(header: 't=1729999700,v1=$_digestAt1729999700'),
        WebhookCheck.ok,
      );
    });

    test('honours a wider tolerance', () {
      const hour = Duration(hours: 1);
      expect(
        _check(
          header: 't=1729999699,v1=$_digestAt1729999699',
          tolerance: hour,
        ),
        WebhookCheck.ok,
      );
    });

    test('refuses a digest that is not hex or the wrong length', () {
      expect(
        _check(header: 't=1730000000,v1=zz$_digestAt1730000000'),
        WebhookCheck.signatureMismatch,
      );
      expect(
        _check(header: 't=1730000000,v1=5668a8c0'),
        WebhookCheck.signatureMismatch,
      );
    });
  });

  group('constantTimeEquals', () {
    test('agrees with list equality where it can', () {
      final bytes = utf8.encode(_eventBody);
      expect(constantTimeEquals(bytes, utf8.encode(_eventBody)), isTrue);
      expect(
        constantTimeEquals(bytes, utf8.encode('${_eventBody}x')),
        isFalse,
      );
    });

    test('does not depend on where the bytes first differ', () {
      final a = List<int>.filled(32, 0);
      for (final position in [0, 16, 31]) {
        final b = List<int>.from(a);
        b[position] = 1;
        expect(constantTimeEquals(a, b), isFalse, reason: 'at $position');
      }
      expect(constantTimeEquals(a, List<int>.from(a)), isTrue);
    });

    test('rejects a length mismatch without reading further', () {
      expect(constantTimeEquals(<int>[1, 2], <int>[1, 2, 3]), isFalse);
      expect(constantTimeEquals(<int>[], <int>[]), isTrue);
    });
  });
}
