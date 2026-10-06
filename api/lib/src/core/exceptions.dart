class AppException implements Exception {
  const AppException(this.statusCode, this.error, {this.details});

  final int statusCode;
  final String error;
  final List<Map<String, String>>? details;

  @override
  String toString() => 'AppException($statusCode): $error';
}

class BadRequestException extends AppException {
  const BadRequestException([String error = 'Bad request']) : super(400, error);
}

class UnauthorizedException extends AppException {
  const UnauthorizedException([String error = 'Unauthorized'])
    : super(401, error);
}

class ForbiddenException extends AppException {
  const ForbiddenException([String error = 'Forbidden']) : super(403, error);
}

class NotFoundException extends AppException {
  const NotFoundException([String error = 'Not found']) : super(404, error);
}

class ConflictException extends AppException {
  const ConflictException([String error = 'Conflict']) : super(409, error);
}

class InvalidEntityException extends AppException {
  InvalidEntityException(List<String> messages)
    : super(
        422,
        'Invalid Entity',
        details: [
          for (final message in messages) {'type': 'field', 'message': message},
        ],
      );
}

class InternalServerException extends AppException {
  const InternalServerException([String error = 'Internal server error'])
    : super(500, error);
}

class BadGatewayException extends AppException {
  const BadGatewayException([String error = 'Bad gateway']) : super(502, error);
}

class DatabaseConnectionFailedException extends AppException {
  const DatabaseConnectionFailedException()
    : super(503, 'Database connection failed');
}
