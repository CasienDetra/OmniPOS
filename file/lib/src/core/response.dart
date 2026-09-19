import 'package:dart_frog/dart_frog.dart';

import 'exceptions.dart';

const corsHeaders = <String, Object>{'access-control-allow-origin': '*'};

String formatTimestamp(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  final hours24 = date.hour;
  final hours12 = hours24 % 12 == 0 ? 12 : hours24 % 12;
  final period = hours24 >= 12 ? 'PM' : 'AM';
  return '${pad(date.day)}-${pad(date.month)}-${date.year} '
      '${pad(hours12)}:${pad(date.minute)}:${pad(date.second)} $period';
}

Response jsonSuccess(
  Object? data, {
  String? message,
  int statusCode = 200,
}) {
  return Response.json(
    statusCode: statusCode,
    headers: corsHeaders,
    body: {
      'success': true,
      'status_code': statusCode,
      if (message != null) 'message': message,
      'data': data,
    },
  );
}

Response jsonErrorEnvelope(AppException exception, {required String path}) {
  return Response.json(
    statusCode: exception.statusCode,
    headers: corsHeaders,
    body: {
      'success': false,
      'status_code': exception.statusCode,
      'error': exception.error,
      if (exception.details != null) 'errors': exception.details,
      'timestamp': formatTimestamp(DateTime.now()),
      'path': path,
    },
  );
}
