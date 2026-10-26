import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

final _fileService = FileService();

/// Unauthenticated proxy to the file service's upload-base64 endpoint
/// (v4 /api/testing/upload/file parity).
Future<Response> _post(RequestContext context) async {
  final body = await jsonBody(context);
  final validator = Validator();
  final folder = validator.optionalString(body, 'folder') ?? 'testing';
  final image = validator.requireString(body, 'image');
  if (image.isNotEmpty) validateBase64Image(validator, image);
  validator.throwIfInvalid();

  final data = await _fileService.uploadBase64Image(folder, image);
  return jsonSuccess(data, message: 'File has been uploaded successfully.');
}
