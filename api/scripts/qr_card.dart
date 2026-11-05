// Draws a payment's KHQR as a counter card: amount on top, code below, a
// medallion over the centre — the layout CutLuy's own demo page uses, and the
// reason error correction level H is the one the renderer asks for. A code that
// survives a logo over ~7% of its area survives this.
//
// Usage: dart run scripts/qr_card.dart [base-url] [--tran=<id>] [--qty=<n>] [--out=<path>]
//   --tran  draw a payment that already exists instead of opening a new one
//   --qty   how many of the first catalogue product to sell (default 1)
//   --out   where the HTML lands (default build/qr-card.html)
//
// The page is self-contained — the SVG is inlined — so it opens from disk with
// no server and no token. That is why this is a script and not a web page: the
// endpoint needs a cashier bearer token, and a `file://` page cannot present
// one without a CORS preflight the API does not answer.
//
// Opening a payment spends one of the gateway's create calls, so pass --tran to
// redraw something that is already on the counter.
//
// POS_USERNAME and POS_PASSWORD must name a cashier; the seed script prints the
// credentials it created.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> argv) async {
  var base = 'http://localhost:3000';
  var tranId = '';
  var quantity = 1;
  var outPath = 'build/qr-card.html';
  for (final arg in argv) {
    if (arg.startsWith('--tran=')) {
      tranId = arg.substring(7);
    } else if (arg.startsWith('--out=')) {
      outPath = arg.substring(6);
    } else if (arg.startsWith('--qty=')) {
      quantity = int.tryParse(arg.substring(6)) ?? quantity;
    } else if (!arg.startsWith('--')) {
      base = arg;
    }
  }

  final client = HttpClient();
  Future<(int, String)> send(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final request = await client.openUrl(method, Uri.parse('$base$path'));
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    return (response.statusCode, text);
  }

  final username = Platform.environment['POS_USERNAME'] ?? '';
  final password = Platform.environment['POS_PASSWORD'] ?? '';
  if (username.isEmpty || password.isEmpty) {
    exitWith(
      'set POS_USERNAME and POS_PASSWORD to a cashier (the seed script prints '
      'the ones it created)',
    );
  }
  final login = await send(
    'POST',
    '/api/v1/account/auth/login',
    body: {'username': username, 'password': password},
  );
  if (login.$1 != 200) {
    exitWith('login failed (${login.$1}): ${login.$2}');
  }
  final token =
      ((jsonDecode(login.$2) as Map)['data'] as Map)['token'] as String;

  Map<String, dynamic> payment;
  if (tranId.isEmpty) {
    final catalogue = await send(
      'GET',
      '/api/v1/cashier/ordering/products',
      token: token,
    );
    if (catalogue.$1 != 200) {
      exitWith('catalogue read failed (${catalogue.$1}): ${catalogue.$2}');
    }
    final productId = firstProductId(
      jsonDecode(catalogue.$2) as Map<String, dynamic>,
    );
    if (productId == null) {
      exitWith('the catalogue has no active product to sell — run seed.dart');
    }
    final opened = await send(
      'POST',
      '/api/v1/cashier/payments',
      token: token,
      body: {
        'cart': jsonEncode({productId: quantity}),
        'platform': 'Web',
      },
    );
    if (opened.$1 != 201) {
      exitWith('opening a QR failed (${opened.$1}): ${opened.$2}');
    }
    payment = (jsonDecode(opened.$2) as Map)['data'] as Map<String, dynamic>;
  } else {
    final read = await send(
      'GET',
      '/api/v1/cashier/payments/$tranId',
      token: token,
    );
    if (read.$1 != 200) {
      exitWith('payment read failed (${read.$1}): ${read.$2}');
    }
    payment = (jsonDecode(read.$2) as Map)['data'] as Map<String, dynamic>;
  }

  tranId = payment['tran_id'] as String;
  final status = payment['status'] as String;
  if (status != 'pending') {
    exitWith(
      'payment $tranId is $status, so the API will not draw its code — '
      'open a fresh one without --tran',
    );
  }
  final drawn = await send(
    'GET',
    '/api/v1/cashier/payments/$tranId/qr',
    token: token,
  );
  if (drawn.$1 != 200) {
    exitWith('the QR endpoint answered ${drawn.$1}: ${drawn.$2}');
  }

  final html = renderCard(payment, drawn.$2);
  final out = File(outPath);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(html);
  client.close(force: true);
  stdout.writeln(
    '${out.absolute.path}  ($tranId, ${payment['charge_amount']} '
    '${payment['charge_currency']})',
  );
}

/// The first product the ordering screen offers, so the card has a real price.
String? firstProductId(Map<String, dynamic> envelope) {
  for (final type in (envelope['data'] as List).cast<Map<String, dynamic>>()) {
    for (final product
        in (type['products'] as List).cast<Map<String, dynamic>>()) {
      final id = product['id'];
      if (id is String && id.isNotEmpty) return id;
    }
  }
  return null;
}

String renderCard(Map<String, dynamic> payment, String svg) {
  final chargeCurrency = (payment['charge_currency'] as String).toUpperCase();
  final chargeAmount = payment['charge_amount'] as num;
  final shopAmount = payment['amount'] as num;
  final shopCurrency = (payment['currency'] as String).toUpperCase();
  final rate = payment['exchange_rate'];
  final expiresAt = DateTime.parse(payment['expires_at'] as String);
  final big = formatAmount(chargeAmount, chargeCurrency);
  final glyph = chargeCurrency == 'KHR' ? '៛' : r'$';
  // Only worth a second line when the till books one currency and the customer
  // pays in another, which is what CutLuy forces on a riel shelf.
  final rateNote = rate is num
      ? '  ·  1 USD = ${formatAmount(rate, 'KHR')} KHR'
      : '';
  final converted = chargeCurrency == shopCurrency
      ? null
      : '${formatAmount(shopAmount, shopCurrency)} $shopCurrency$rateNote';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escape(payment['tran_id'].toString())} — pay by KHQR</title>
<style>
  :root { color-scheme: light; }
  body {
    margin: 0; min-height: 100vh; display: grid; place-items: center;
    background: #eef0f3;
    font-family: -apple-system, "Segoe UI", Roboto, "Noto Sans Khmer", sans-serif;
  }
  .card {
    position: relative; width: 300px; background: #fff; overflow: hidden;
    border-radius: 14px; box-shadow: 0 1px 2px rgba(16,20,28,.10),
      0 12px 32px rgba(16,20,28,.10);
  }
  .fold {
    position: absolute; top: 0; right: 0; width: 0; height: 0;
    border-top: 30px solid #d92d20; border-left: 30px solid transparent;
  }
  header { padding: 16px 18px 12px; border-bottom: 1px dashed #d8dce2; }
  .who { font-size: 12px; letter-spacing: .02em; color: #6b7280; }
  .total { display: flex; align-items: baseline; gap: 7px; margin-top: 3px; }
  .total b { font-size: 26px; font-weight: 650; color: #10141c; }
  .total span { font-size: 13px; color: #6b7280; }
  .sub { margin-top: 3px; font-size: 11.5px; color: #8a929e; }
  .code { position: relative; padding: 14px; }
  .code svg { display: block; width: 100%; height: auto; }
  .medallion {
    position: absolute; top: 50%; left: 50%; transform: translate(-50%,-50%);
    width: 26%; aspect-ratio: 1; border-radius: 50%; background: #10141c;
    color: #fff; display: grid; place-items: center;
    font-size: 46px; font-weight: 600; box-shadow: 0 0 0 4px #fff;
  }
  footer { padding: 0 18px 16px; font-size: 11.5px; color: #8a929e; }
  .clock { color: #10141c; font-weight: 600; }
  .gone {
    position: absolute; inset: 14px; background: #fff; display: none;
    place-items: center; text-align: center; font-size: 14px; color: #4b5563;
  }
  .expired .gone { display: grid; }
</style>
</head>
<body>
<div class="card" id="card">
  <div class="fold"></div>
  <header>
    <div class="who">${escape(label(payment))}</div>
    <div class="total"><b>${escape(big)}</b><span>${escape(chargeCurrency)}</span></div>
    ${converted == null ? '' : '<div class="sub">${escape(converted)}</div>'}
  </header>
  <div class="code">
    $svg
    <div class="medallion">$glyph</div>
    <div class="gone">This code has expired.<br>Ask the counter for a new one.</div>
  </div>
  <footer>
    Scan with any KHQR wallet · <span class="clock" id="clock">&nbsp;</span><br>
    ${escape(payment['tran_id'].toString())}
  </footer>
</div>
<script>
  // The card retires itself at the moment the gateway stops honouring the code,
  // which is the rule the API enforces with a 410 on the image endpoint.
  const until = Date.parse('${escape(expiresAt.toIso8601String())}');
  const clock = document.getElementById('clock');
  setInterval(() => {
    const left = Math.round((until - Date.now()) / 1000);
    if (left <= 0) {
      document.getElementById('card').classList.add('expired');
      clock.textContent = 'expired';
      return;
    }
    clock.textContent =
        'expires in ' + Math.floor(left / 60) + 'm ' + (left % 60) + 's';
  }, 1000);
</script>
</body>
</html>
''';
}

/// Whose code this is, in the words the counter already has.
String label(Map<String, dynamic> payment) {
  // The row stores the provider in the lowercase form the environment uses;
  // both gateways write their own names with an internal capital.
  const names = {'cutluy': 'CutLuy', 'payway': 'PayWay'};
  final provider = payment['provider'] as String? ?? '';
  final name = '${names[provider] ?? _capitalise(provider)} payment';
  return '$name · ${payment['platform']}';
}

String _capitalise(String value) =>
    value.isEmpty ? 'KHQR' : value[0].toUpperCase() + value.substring(1);

String formatAmount(num amount, String currency) {
  final whole = amount.round();
  if (currency == 'KHR') {
    return '$whole'.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]},',
    );
  }
  return amount.toStringAsFixed(2);
}

String escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

Never exitWith(String message) {
  stderr.writeln(message);
  exit(1);
}
