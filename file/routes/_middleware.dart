import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart' show MongoDartError;
import 'package:pos_file/pos_file.dart';

/// Global error boundary, mirroring v4's ExceptionErrorsFilter: every
/// exception raised by a route handler is converted into the shared JSON
/// error envelope.
Handler middleware(Handler handler) {
  return (context) async {
    final path = '/${context.request.url.path}';
    try {
      return await handler(context);
    } on AppException catch (exception) {
      return jsonErrorEnvelope(exception, path: path);
    } on TimeoutException {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } on SocketException {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } on MongoDartError {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } catch (exception, stackTrace) {
      stderr.writeln('Unhandled error: $exception\n$stackTrace');
      return jsonErrorEnvelope(
        const InternalServerException('Internal server error'),
        path: path,
      );
    }
  };
}
