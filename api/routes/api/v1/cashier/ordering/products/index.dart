import 'package:dart_frog/dart_frog.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;
import 'package:pos_api/pos_api.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => await _get(context),
    _ => Response(statusCode: 405),
  };
}

/// Ordering screen payload: every product type with its nested active
/// products (v4 returned types via ordering/products include).
Future<Response> _get(RequestContext context) async {
  requireRole(context, Role.cashier);
  final typeDocs = await findPage(
    collection: 'product_types',
    sort: {'name': 1},
    limit: 200,
  );
  final types = <Map<String, Object?>>[];
  for (final typeDoc in typeDocs) {
    final productDocs = await findPage(
      collection: 'products',
      filter: {'type_id': typeDoc['_id'], 'is_active': true},
      sort: {'name': 1},
      limit: 500,
    );
    types.add({
      'id': idHex(typeDoc['_id'] as ObjectId?),
      'name': typeDoc['name'],
      'products': [
        for (final doc in productDocs) Product.fromDocument(doc).toJson(),
      ],
    });
  }
  return jsonSuccess(types);
}
