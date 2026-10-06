import 'package:mongo_dart/mongo_dart.dart';

import 'exceptions.dart';

Map<String, Object?> buildPagination({
  required int page,
  required int limit,
  required int total,
}) {
  return {
    'page': page,
    'limit': limit,
    'totalPage': (total / limit).ceil(),
    'total': total,
  };
}

/// Parses a route/id string into an [ObjectId]; throws 404 (like v4's
/// ParseIntPipe failing) for malformed ids.
ObjectId asObjectId(String raw) {
  final id = ObjectId.tryParse(raw);
  if (id == null) {
    throw NotFoundException('Invalid id "$raw"');
  }
  return id;
}

String idHex(ObjectId? id) => id?.oid ?? '';

DateTime? parseDateParam(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}
