import 'dart:convert';

import 'package:crypto/crypto.dart';

/// What went wrong with a webhook delivery, in the order the checks are made.
enum WebhookCheck {
  /// The delivery is authentic and fresh.
  ok,

  /// No signature header at all.
  headerMissing,

  /// The header is not in the `t=<unix>,v1=<hex>` shape.
  headerMalformed,

  /// The header carries a timestamp outside the accepted window.
  timestampStale,

  /// The computed digest does not match the one delivered.
  signatureMismatch,
}

/// The payload digest a `t=…,v1=…` signature promises:
/// `hex(HMAC-SHA256(secret, "<t>."<rawBody>"))`.
///
/// The timestamp is inside the signed string, so a delivery cannot be replayed
/// with a fresh timestamp without breaking the digest.
String webhookDigestHex({
  required String secret,
  required List<int> rawBody,
  required int timestamp,
}) {
  final hmac = Hmac(sha256, utf8.encode(secret));
  final signed = <int>[
    ...utf8.encode('$timestamp.'),
    ...rawBody,
  ];
  return hmac.convert(signed).toString();
}

/// Compares two byte sequences without the loop depending on where they first
/// differ. `==` on strings stops at the first mismatched character, which turns
/// a signature check into an oracle an attacker can query repeatedly.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a[i] ^ b[i];
  }
  return difference == 0;
}

/// Verifies a webhook delivery: signature over the raw bytes, then the age of
/// its timestamp, then the digest itself.
///
/// [rawBody] must be the bytes as they arrived. Re-encoding a parsed body
/// changes it — key order, spacing, number formatting — and the digest of the
/// result does not match the one the sender computed. That is why this takes
/// bytes and why the route that calls it reads them before any JSON parsing.
///
/// A stale timestamp is refused rather than ignored: the digest is reproducible
/// forever once a secret leaks, so the window is what stops an intercepted
/// delivery from being replayed next month.
WebhookCheck checkWebhookSignature({
  required String? secret,
  required String? header,
  required List<int> rawBody,
  required DateTime now,
  Duration tolerance = const Duration(minutes: 5),
}) {
  if (secret == null || secret.isEmpty || header == null || header.isEmpty) {
    return WebhookCheck.headerMissing;
  }
  final timestamp = _field(header, 't');
  final delivered = _field(header, 'v1');
  if (timestamp == null || delivered == null) {
    return WebhookCheck.headerMalformed;
  }
  final seconds = int.tryParse(timestamp);
  if (seconds == null) return WebhookCheck.headerMalformed;
  final age = now
      .toUtc()
      .difference(
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      )
      .abs();
  if (age > tolerance) return WebhookCheck.timestampStale;

  final expected = webhookDigestHex(
    secret: secret,
    rawBody: rawBody,
    timestamp: seconds,
  );
  final expectedBytes = _hexToBytes(expected);
  final deliveredBytes = _hexToBytes(delivered);
  if (expectedBytes == null || deliveredBytes == null) {
    return WebhookCheck.signatureMismatch;
  }
  return constantTimeEquals(expectedBytes, deliveredBytes)
      ? WebhookCheck.ok
      : WebhookCheck.signatureMismatch;
}

String? _field(String header, String name) {
  // Split on commas, then on the first equals: a signature value is hex, but a
  // sender that adds a field later should not make every message unreadable.
  for (final part in header.split(',')) {
    final separator = part.indexOf('=');
    if (separator < 0) continue;
    if (part.substring(0, separator).trim() == name) {
      final value = part.substring(separator + 1).trim();
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

List<int>? _hexToBytes(String hex) {
  if (hex.length.isOdd) return null;
  final bytes = <int>[];
  for (var i = 0; i < hex.length; i += 2) {
    final byte = int.tryParse(hex.substring(i, i + 2), radix: 16);
    if (byte == null) return null;
    bytes.add(byte);
  }
  return bytes;
}
