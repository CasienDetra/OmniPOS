import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart' show MongoDartError;
import 'package:pos_api/pos_api.dart';

/// v4's public route list: the probes, health, login and the testing endpoints
/// are the only paths that work without a bearer token. Readiness must stay
/// unauthenticated or an orchestrator can never observe it.
const _publicPaths = {'/', '/healthz', '/readyz', '/openapi', '/swagger'};

/// Global error boundary (v4 ExceptionErrorsFilter) wrapping the auth guard,
/// so 401/403 raised during authentication also get the JSON envelope.
Handler middleware(Handler handler) {
  final guarded = _authGuard(handler);
  return (context) async {
    final path = '/${context.request.url.path}';
    try {
      return await guarded(context);
    } on AppException catch (exception) {
      return jsonErrorEnvelope(exception, path: path);
    } on TimeoutException {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } on SocketException {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } on MongoDartError {
      return jsonErrorEnvelope(
        const DatabaseConnectionFailedException(),
        path: path,
      );
    } catch (exception, stackTrace) {
      stderr.writeln('Unhandled error: $exception\n$stackTrace');
      return jsonErrorEnvelope(
        const InternalServerException('Internal server error'),
        path: path,
      );
    }
  };
}

Handler _authGuard(Handler handler) {
  const tokens = TokenService();
  return (context) async {
    final path = '/${context.request.url.path}';
    final isPublic =
        _publicPaths.contains(path) ||
        publicApiPrefixes.any(
          (prefix) => path == prefix || path.startsWith('$prefix/'),
        );

    final header = context.request.headers['authorization'];
    AuthUser? auth;
    if (header != null && header.isNotEmpty) {
      final parts = header.split(' ');
      if (parts.length != 2 || parts.first.toLowerCase() != 'bearer') {
        throw const UnauthorizedException(
          'Authorization header must be "Bearer <token>"',
        );
      }
      // A token is always verified when present, even on public paths.
      auth = tokens.verify(parts.last);
    } else if (!isPublic) {
      throw const UnauthorizedException('Token not provided');
    }

    if (auth != null) {
      // Match on the first segment under the version prefix instead of a
      // literal "/api/admin", so bumping the version can never leave a guard
      // that silently matches nothing. The segment names are the route
      // directory names; api_routes_test.dart pins them.
      final section = path.startsWith('$apiPrefix/')
          ? path.substring(apiPrefix.length + 1).split('/').first
          : null;
      if (section == adminSection && !auth.hasRole(Role.admin)) {
        throw const ForbiddenException('Requires Admin role');
      }
      if (section == cashierSection && !auth.hasRole(Role.cashier)) {
        throw const ForbiddenException('Requires Cashier role');
      }
      return handler(context.provide<AuthUser>(() => auth!));
    }
    return handler(context);
  };
}
