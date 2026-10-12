import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:pos_file/pos_file.dart';

/// Readiness: the database answers and the upload directory accepts a real
/// write, so a read-only mount or a missing volume fails the probe instead of
/// surfacing later as a lost order attachment.
Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _ready(),
    _ => Response(statusCode: 405),
  };
}

Future<Response> _ready() async {
  await MongoDb.instance.database;
  await _assertUploadWritable();
  return jsonSuccess({'status': 'ready'});
}

Future<void> _assertUploadWritable() async {
  final directory = Directory(AppConfig.current.uploadDir);
  if (!await directory.exists()) {
    throw const InternalServerException('Upload directory is missing');
  }
  final probe = File(p.join(directory.path, '.healthz-probe'));
  try {
    await probe.writeAsString(DateTime.now().toUtc().toIso8601String());
  } on FileSystemException {
    throw const InternalServerException('Upload directory is not writable');
  } finally {
    try {
      await probe.delete();
    } on FileSystemException {
      // Nothing to clean up when the write itself failed.
    }
  }
}
