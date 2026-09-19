import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/exceptions.dart';
import '../database/mongo_db.dart';
import '../models/file_record.dart';

final folderPattern = RegExp(r'^[A-Za-z0-9-]{2,64}$');
final base64ImagePattern =
    RegExp(r'^data:image/(png|jpg|jpeg|gif);base64,[A-Za-z0-9+/]+={0,2}$');
final filenamePattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Validates the `folder` field the same way file-v3's express-validator did;
/// appends messages to [errors] and returns `unknown` when invalid.
String validateFolder(String? raw, List<String> errors) {
  final folder = raw?.trim() ?? '';
  if (folder.isEmpty) {
    errors.add('folder is required and must be at least 2 characters long');
    return 'unknown';
  }
  if (!folderPattern.hasMatch(folder)) {
    errors.add('folder may only contain letters, numbers and dashes');
    return 'unknown';
  }
  return folder;
}

typedef DecodedImage = ({Uint8List bytes, String mimetype, String subtype});

/// Decodes a data-URL image string, or returns null when it does not match the
/// file-v3 data-URL pattern.
DecodedImage? decodeBase64Image(String image) {
  final match = base64ImagePattern.firstMatch(image);
  if (match == null) return null;
  final subtype = match.group(1)!;
  final payload = image.substring(image.indexOf(',') + 1);
  return (
    bytes: base64Decode(payload),
    mimetype: 'image/${subtype == 'jpg' ? 'jpeg' : subtype}',
    subtype: subtype,
  );
}

/// Writes [bytes] to `<uploadDir>/<folder>/<uuid>` (file-v3 layout, filenames
/// carry no extension) and registers the record in the `files` collection.
Future<FileRecord> saveUploadedFile({
  required String folder,
  required String originalname,
  required String mimetype,
  required String encoding,
  required List<int> bytes,
}) async {
  final maxBytes = AppConfig.current.maxUploadBytes;
  if (bytes.length > maxBytes) {
    throw const PayloadTooLargeException(
        'File exceeds the maximum upload size of 512 MB');
  }

  final filename = const Uuid().v4().replaceAll('-', '');
  final file = File(p.join(AppConfig.current.uploadDir, folder, filename));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);

  final saved = await file.readAsBytes();
  if (saved.length != bytes.length) {
    await file.delete();
    throw const InternalServerException('Failed to verify the file on disk');
  }

  final record = FileRecord(
    filename: filename,
    originalname: originalname,
    mimetype: mimetype,
    size: bytes.length,
    encoding: encoding,
    path: file.path,
    createdAt: DateTime.now().toUtc(),
  );

  final collection = await MongoDb.instance.collection('files');
  await collection.insertOne(record.toDocument());
  return record;
}

Future<FileRecord?> findFileByName(String filename) async {
  final collection = await MongoDb.instance.collection('files');
  final doc = await collection.findOne({'filename': filename});
  return FileRecord.fromDocument(doc);
}

Future<void> deleteByName(String filename) async {
  final collection = await MongoDb.instance.collection('files');
  await collection.deleteOne({'filename': filename});
}
