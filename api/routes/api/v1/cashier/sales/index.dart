import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    _ => Response(statusCode: 405),
  };
}

final _service = OrderService();

/// Cashier sees only their own sales (v4 filtered by the token user).
Future<Response> _get(RequestContext context) async {
  final auth = authUser(context);
  final query = listQuery(context);
  final params = context.request.url.queryParameters;
  final result = await _service.list(
    page: query.page,
    limit: query.limit,
    key: query.key,
    cashierId: asObjectId(auth.id),
    platform: emptyToNull(params['platform']),
    startDate: parseDateParam(params['startDate']),
    endDate: parseDateParam(params['endDate']),
    sortBy: query.sort ?? 'ordered_at',
    ascending: query.ascending,
  );
  return jsonSuccess(
    result['data'],
    pagination: result['pagination'] as Map<String, Object?>,
  );
}
