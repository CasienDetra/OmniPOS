import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_file/pos_file.dart';

/// GET /api/file/<filename> — streams the stored file; `?download=true`
/// triggers a download with the original filename (file-v3 contract).
Future<Response> onRequest(RequestContext context, String filename) async {
  if (!filenamePattern.hasMatch(filename)) {
    throw const NotFoundException('File not found');
  }

  final record = await findFileByName(filename);
  if (record == null) {
    throw NotFoundException('File "$filename" not found');
  }

  final file = File(record.path);
  if (!await file.exists()) {
    throw NotFoundException('File "$filename" is missing from disk');
  }

  final download =
      context.request.url.queryParameters['download']?.toLowerCase() == 'true';
  return Response.stream(
    body: file.openRead(),
    headers: {
      ...corsHeaders,
      HttpHeaders.contentTypeHeader: record.mimetype,
      HttpHeaders.contentLengthHeader: '${record.size}',
      if (download)
        'content-disposition': 'attachment; filename="${record.originalname}"',
    },
  );
}
