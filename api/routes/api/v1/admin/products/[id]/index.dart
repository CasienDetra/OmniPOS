import 'package:dart_frog/dart_frog.dart';
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context, id),
    HttpMethod.put => await _put(context, id),
    HttpMethod.delete => await _delete(context, id),
    _ => Response(statusCode: 405),
  };
}

final _service = ProductService();

Future<Response> _get(RequestContext context, String id) async {
  return jsonSuccess(await _service.getJson(id));
}

Future<Response> _put(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  final body = await jsonBody(context);
  final validator = Validator();
  final name = validator.optionalString(body, 'name');
  final code = validator.optionalString(body, 'code');
  final type = validator.optionalString(body, 'type');
  double? unitPrice;
  if (body['unit_price'] != null) {
    unitPrice = validator.requireNumber(body, 'unit_price', positive: true);
  }
  final image = validator.optionalString(body, 'image');
  if (image != null) validateBase64Image(validator, image);
  bool? isActive;
  if (body['is_active'] != null) {
    isActive =
        body['is_active'] == true ||
        body['is_active'] == 1 ||
        body['is_active'] == 'true' ||
        body['is_active'] == '1';
  }
  // Present means "set", even when it is null: that is how a product stops
  // being stock-tracked. Absent means "leave it alone".
  FieldUpdate<int>? stock;
  if (body.containsKey('stock')) {
    stock = (value: validator.optionalInt(body, 'stock', min: 0));
  }
  FieldUpdate<int>? lowStockThreshold;
  if (body.containsKey('low_stock_threshold')) {
    lowStockThreshold = (
      value: validator.optionalInt(body, 'low_stock_threshold', min: 0),
    );
  }
  validator.throwIfInvalid();

  await _service.update(
    id,
    name: name,
    code: code,
    typeId: type == null ? null : asObjectId(type),
    unitPrice: unitPrice,
    image: image,
    isActive: isActive,
    stock: stock,
    lowStockThreshold: lowStockThreshold,
  );
  return jsonSuccess(
    await _service.getJson(id),
    message: 'Product has been updated.',
  );
}

Future<Response> _delete(RequestContext context, String id) async {
  requireRole(context, Role.admin);
  await _service.delete(id);
  return jsonSuccess(null, message: 'Product has been deleted.');
}
