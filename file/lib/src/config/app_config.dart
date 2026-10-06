import 'package:dotenv/dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.mongoUri,
    required this.port,
    required this.uploadDir,
    required this.maxUploadBytes,
  });

  static AppConfig? _current;
  static AppConfig get current => _current ??= AppConfig.fromEnvironment();

  final String mongoUri;
  final int port;
  final String uploadDir;
  final int maxUploadBytes;

  factory AppConfig.fromEnvironment() {
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)
      ..load(['.env']);

    String read(String key, String fallback) {
      final value = env[key];
      return (value == null || value.isEmpty) ? fallback : value;
    }

    final directUri = read('MONGODB_URI', '');
    final username = read('MONGO_USERNAME', '');
    final password = Uri.encodeComponent(read('MONGO_PASSWORD', ''));
    final auth = username.isEmpty ? '' : '$username:$password@';
    final mongoUri = directUri.isNotEmpty
        ? directUri
        : 'mongodb://$auth${read('MONGO_HOST', 'localhost')}:'
              '${read('MONGO_PORT', '27017')}/${read('MONGO_DATABASE', 'pos_file')}';

    return AppConfig(
      mongoUri: mongoUri,
      port: int.tryParse(read('PORT', '8080')) ?? 8080,
      uploadDir: read('UPLOAD_DIR', 'public/uploads'),
      maxUploadBytes:
          int.tryParse(read('MAX_UPLOAD_BYTES', '')) ?? 512 * 1024 * 1024,
    );
  }
}
