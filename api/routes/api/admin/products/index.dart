import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    HttpMethod.post => await _post(context),
    _ => Response(statusCode: 405),
  };
}

final _service = ProductService();

Future<Response> _get(RequestContext context) async {
  final query = listQuery(context);
  final params = context.request.url.queryParameters;
  final result = await _service.list(
    page: query.page,
    limit: query.limit,
    key: query.key,
    type: emptyToNull(params['type']),
    creator: emptyToNull(params['creator']),
    startDate: parseDateParam(params['startDate']),
    endDate: parseDateParam(params['endDate']),
    sortBy: query.sort ?? 'name',
    ascending: query.ascending,
  );
  return jsonSuccess(
    result['data'],
    pagination: result['pagination'] as Map<String, Object?>,
  );
}

Future<Response> _post(RequestContext context) async {
  requireRole(context, Role.admin);
  final auth = authUser(context);
  final body = await jsonBody(context);
  final validator = Validator();
  final name = validator.requireString(body, 'name');
  final code = validator.requireString(body, 'code');
  final type = validator.requireString(body, 'type');
  final unitPrice = validator.requireNumber(body, 'unit_price', positive: true);
  final image = validator.optionalString(body, 'image');
  if (image != null) validateBase64Image(validator, image);
  validator.throwIfInvalid();

  final product = await _service.create(
    name: name,
    code: code,
    typeId: asObjectId(type),
    unitPrice: unitPrice,
    image: image,
    creatorId: asObjectId(auth.id),
    isActive:
        body['is_active'] == null ? true : _boolFrom(body['is_active']),
  );
  return jsonSuccess(
    await _service.getJson(idHex(product.id!)),
    statusCode: 201,
    message: 'Product has been created.',
  );
}

bool _boolFrom(Object? value) =>
    value == true || value == 1 || value == '1' || value == 'true';
