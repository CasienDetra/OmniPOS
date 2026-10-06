import 'package:dart_frog/dart_frog.dart';
import 'package:pos_file/pos_file.dart';

/// POST /api/file/upload-base64 — JSON `{folder, image}` where `image` is a
/// data-URL (file-v3 contract used by the POS api service).
Future<Response> onRequest(RequestContext context) async {
  final Object? body;
  try {
    body = await context.request.json();
  } on FormatException {
    throw const BadRequestException('Expected a JSON body with folder/image.');
  }
  if (body is! Map) {
    throw const BadRequestException('Expected a JSON object body.');
  }

  final errors = <String>[];
  final folder = validateFolder(body['folder'] as String?, errors);

  final image = body['image'];
  DecodedImage? decoded;
  if (image is! String || image.isEmpty) {
    errors.add('image is required');
  } else {
    decoded = decodeBase64Image(image);
    if (decoded == null) {
      errors.add(
        'image must be a base64 data URL of a png, jpg, jpeg or gif image',
      );
    }
  }
  if (errors.isNotEmpty) {
    throw InvalidEntityException(errors);
  }

  final data = decoded!;
  final record = await saveUploadedFile(
    folder: folder,
    originalname: '${DateTime.now().microsecondsSinceEpoch}.${data.subtype}',
    mimetype: data.mimetype,
    encoding: 'from-base64',
    bytes: data.bytes,
  );

  return jsonSuccess(
    record.uploadData(),
    message: 'File has been uploaded successfully.',
  );
}
