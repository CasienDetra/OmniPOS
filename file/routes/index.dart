import 'package:dart_frog/dart_frog.dart';
import 'package:pos_file/pos_file.dart';

Response onRequest(RequestContext context) {
  return jsonSuccess({'service': 'pos-file', 'status': 'ok'});
}
