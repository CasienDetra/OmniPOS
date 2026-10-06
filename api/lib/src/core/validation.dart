import 'package:dart_frog/dart_frog.dart';

import 'exceptions.dart';

/// Reads and validates a JSON object request body.
Future<Map<String, dynamic>> jsonBody(RequestContext context) async {
  final Object? body;
  try {
    body = await context.request.json();
  } on FormatException {
    throw const BadRequestException('Request body must be valid JSON');
  }
  if (body is! Map) {
    throw const BadRequestException('Expected a JSON object body');
  }
  return body.cast<String, dynamic>();
}

int queryInt(
  Map<String, String> params,
  String key,
  int fallback, {
  int min = 1,
  int max = 200,
}) {
  final value = int.tryParse(params[key] ?? '');
  if (value == null) return fallback;
  return value.clamp(min, max);
}

bool queryBool(
  Map<String, String> params,
  String key, {
  bool fallback = false,
}) {
  final value = params[key]?.toLowerCase();
  if (value == null || value.isEmpty) return fallback;
  return value == 'true' || value == '1';
}

/// Parses `?page&limit&key&type&creator&startDate&endDate&sort_by&order`
/// style list query parameters into a normalized record.
({int page, int limit, String? key, String? sort, bool ascending}) listQuery(
  RequestContext context,
) {
  final params = context.request.url.queryParameters;
  return (
    page: queryInt(params, 'page', 1),
    limit: queryInt(params, 'limit', 10, min: 1, max: 100),
    key: emptyToNull(params['key']),
    sort: emptyToNull(params['sort_by']) ?? emptyToNull(params['sort']),
    ascending: (emptyToNull(params['order']) ?? 'ASC').toUpperCase() == 'ASC',
  );
}

String? emptyToNull(String? value) =>
    (value == null || value.trim().isEmpty) ? null : value.trim();

class Validator {
  final List<String> errors = [];

  String requireString(
    Map<String, dynamic> body,
    String field, {
    int? maxLength,
  }) {
    final value = body[field];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$field is required');
      return '';
    }
    if (maxLength != null && value.length > maxLength) {
      errors.add('$field must be shorter than $maxLength characters');
      return '';
    }
    return value.trim();
  }

  String? optionalString(Map<String, dynamic> body, String field) {
    final value = body[field];
    if (value == null) return null;
    if (value is! String) {
      errors.add('$field must be a string');
      return null;
    }
    return value.trim().isEmpty ? null : value.trim();
  }

  double requireNumber(
    Map<String, dynamic> body,
    String field, {
    bool positive = false,
  }) {
    final value = body[field];
    final number = value is num ? value.toDouble() : double.tryParse('$value');
    if (number == null) {
      errors.add('$field must be a number');
      return 0;
    }
    if (positive && number <= 0) {
      errors.add('$field must be a positive number');
      return 0;
    }
    return number;
  }

  int requireInt(Map<String, dynamic> body, String field) {
    final value = body[field];
    final number = value is num ? value.toInt() : int.tryParse('$value');
    if (number == null) {
      errors.add('$field is required');
      return 0;
    }
    return number;
  }

  void throwIfInvalid() {
    if (errors.isNotEmpty) {
      throw InvalidEntityException(errors);
    }
  }
}

final base64ImagePattern = RegExp(
  r'^data:image/(png|jpg|jpeg|gif);base64,[A-Za-z0-9+/]+={0,2}$',
);

void validateBase64Image(Validator v, String? image, {bool required = true}) {
  if (image == null || image.isEmpty) {
    if (required) v.errors.add('image is required');
    return;
  }
  if (!base64ImagePattern.hasMatch(image)) {
    v.errors.add('image must be a base64 data URL of a png or jpg image');
  }
}
