import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../core/exceptions.dart';

/// HTTP client for the POS file service (v4's FileService equivalent).
class FileService {
  FileService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String get _baseUrl => AppConfig.current.fileBaseUrl;

  /// Uploads a base64 data-URL image to `<file>/api/file/upload-base64`
  /// and returns the payload `{uri, filename, originalname, mimetype, ...}`.
  Future<Map<String, Object?>> uploadBase64Image(
    String folder,
    String base64Image,
  ) async {
    late final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$_baseUrl/api/file/upload-base64'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({'folder': folder, 'image': base64Image}),
          )
          .timeout(const Duration(seconds: 30));
    } on SocketException {
      throw const BadGatewayException('File service connection failed');
    } on TimeoutException {
      throw const BadGatewayException('File service request timed out');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final body = decoded is Map ? decoded.cast<String, Object?>() : null;
    if (response.statusCode != 200 || body?['success'] != true) {
      final error = body?['error'] ?? body?['message'] ?? 'unknown error';
      throw BadGatewayException('File service upload failed: $error');
    }
    final data = body?['data'];
    if (data is! Map) {
      throw const BadGatewayException('File service returned no payload');
    }
    return data.cast<String, Object?>();
  }

  void close() => _client.close();
}
