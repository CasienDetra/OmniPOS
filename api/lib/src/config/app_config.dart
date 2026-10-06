import 'package:dotenv/dotenv.dart';

class AppConfig {
  const AppConfig({
    required this.mongoUri,
    required this.port,
    required this.jwtSecret,
    required this.fileBaseUrl,
  });

  static AppConfig? _current;
  static AppConfig get current => _current ??= AppConfig.fromEnvironment();

  final String mongoUri;
  final int port;
  final String jwtSecret;
  final String fileBaseUrl;

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
              '${read('MONGO_PORT', '27017')}/${read('MONGO_DATABASE', 'pos_api')}';

    return AppConfig(
      mongoUri: mongoUri,
      port: int.tryParse(read('PORT', '3000')) ?? 3000,
      jwtSecret: read('JWT_SECRET', 'change-me-in-production'),
      fileBaseUrl: read('FILE_BASE_URL', 'http://localhost:8080'),
    );
  }
}
