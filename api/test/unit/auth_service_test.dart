import 'package:pos_api/pos_api.dart';
import 'package:test/test.dart';

void main() {
  group('password hashing', () {
    test('bcrypt round-trip verifies', () {
      final hash = AuthService.hashPassword('cashier123');
      expect(hash, isNot('cashier123'));
      expect(AuthService.verifyPassword('cashier123', hash), isTrue);
      expect(AuthService.verifyPassword('wrong', hash), isFalse);
    });

    test('malformed hash does not throw', () {
      expect(AuthService.verifyPassword('x', 'not-a-bcrypt-hash'), isFalse);
    });
  });

  group('DeviceInfo.fromHeaders', () {
    test('detects browser and os from user agent', () {
      final info = DeviceInfo.fromHeaders(
        headers: {
          'user-agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36',
        },
        defaultPlatform: 'Web',
      );
      expect(info.browser, 'Chrome');
      expect(info.os, 'Windows');
      expect(info.platform, 'Web');
    });

    test('prefers first x-forwarded-for entry, falls back to unknown', () {
      final a = DeviceInfo.fromHeaders(
        headers: {'x-forwarded-for': ' 203.0.113.7, 70.41.3.18'},
        defaultPlatform: 'Web',
      );
      expect(a.ip, '203.0.113.7');
      final b = DeviceInfo.fromHeaders(
        headers: {'x-real-ip': '198.51.100.9'},
        defaultPlatform: 'Web',
      );
      expect(b.ip, '198.51.100.9');
      final c = DeviceInfo.fromHeaders(headers: {}, defaultPlatform: 'Web');
      expect(c.ip, 'unknown');
    });
  });
}
