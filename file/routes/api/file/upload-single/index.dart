import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:pos_file/pos_file.dart';

/// POST /api/file/upload-single — multipart form with a `file` part and a
/// `folder` field (file-v3 contract).
Future<Response> onRequest(RequestContext context) async {
  final request = context.request;
  final contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('multipart/form-data')) {
    throw const BadRequestException('Expected a multipart/form-data request.');
  }

  final formData = await request.formData();
  final uploaded = formData.files['file'];
  final errors = <String>[];
  final folder = validateFolder(formData.fields['folder'], errors);
  if (uploaded == null) {
    errors.add('a file part named "file" is required');
  }
  if (errors.isNotEmpty) {
    throw InvalidEntityException(errors);
  }

  final bytes = Uint8List.fromList(await uploaded!.readAsBytes());
  final record = await saveUploadedFile(
    folder: folder,
    originalname: uploaded.name,
    mimetype: uploaded.contentType.mimeType,
    encoding: '7bit',
    bytes: bytes,
  );

  return jsonSuccess(
    record.uploadData(),
    message: 'File has been uploaded successfully.',
  );
}
