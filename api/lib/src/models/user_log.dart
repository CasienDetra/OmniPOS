class UserLog {
  const UserLog({
    required this.action,
    required this.ip,
    required this.browser,
    required this.os,
    required this.platform,
    required this.timestamp,
  });

  static UserLog fromDocument(Map<String, dynamic> doc) => UserLog(
        action: doc['action'] as String? ?? '',
        ip: doc['ip'] as String? ?? '',
        browser: doc['browser'] as String? ?? '',
        os: doc['os'] as String? ?? '',
        platform: doc['platform'] as String? ?? '',
        timestamp: doc['timestamp'] as DateTime? ?? DateTime.now(),
      );

  final String action;
  final String ip;
  final String browser;
  final String os;
  final String platform;
  final DateTime timestamp;

  Map<String, Object?> toDocument() => {
        'action': action,
        'ip': ip,
        'browser': browser,
        'os': os,
        'platform': platform,
        'timestamp': timestamp.toUtc(),
      };

  Map<String, Object?> toJson() => {
        'action': action,
        'ip': ip,
        'browser': browser,
        'os': os,
        'platform': platform,
        'timestamp': timestamp.toIso8601String(),
      };
}
