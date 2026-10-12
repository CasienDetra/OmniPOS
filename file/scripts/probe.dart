// Container healthcheck probe.
//
// The file image installs nothing beyond the AOT binary, so there is no curl
// to healthcheck with. This compiles to a second static executable next to
// /app/server and exits 0 only for a 2xx answer.
import 'dart:io';

Future<void> main(List<String> args) async {
  final url = args.isEmpty ? 'http://127.0.0.1:8080/readyz' : args.first;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 3));
    final response = await request.close().timeout(const Duration(seconds: 3));
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('$url answered ${response.statusCode}');
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('$url: $error');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}
