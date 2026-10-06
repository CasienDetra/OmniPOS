import '../repositories/mongo.dart';

/// Dashboard stats endpoint (v4 a1-dashboard equivalent).
class DashboardService {
  const DashboardService();

  Future<Map<String, Object?>> summary() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day).toUtc();
    final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

    final todayAgg = await aggregate('orders', [
      {
        r'$match': {
          'ordered_at': {r'$gte': startOfToday},
        },
      },
      {
        r'$group': {
          '_id': null,
          'count': {r'$sum': 1},
          'revenue': {r'$sum': r'$total_price'},
        },
      },
    ]);
    final weekAgg = await aggregate('orders', [
      {
        r'$match': {
          'ordered_at': {r'$gte': startOfWeek},
        },
      },
      {
        r'$group': {
          '_id': null,
          'count': {r'$sum': 1},
          'revenue': {r'$sum': r'$total_price'},
        },
      },
    ]);
    final topProducts = await aggregate('orders', [
      {r'$unwind': r'$items'},
      {
        r'$group': {
          '_id': r'$items.product_id',
          'name': {r'$first': r'$items.name'},
          'qty': {r'$sum': r'$items.qty'},
          'revenue': {
            r'$sum': {
              r'$multiply': [r'$items.unit_price', r'$items.qty'],
            },
          },
        },
      },
      {
        r'$sort': {'qty': -1},
      },
      {r'$limit': 5},
    ]);

    final today = todayAgg.isEmpty ? null : todayAgg.first;
    final week = weekAgg.isEmpty ? null : weekAgg.first;

    return {
      'orders_today': (today?['count'] as num?)?.toInt() ?? 0,
      'revenue_today': (today?['revenue'] as num?)?.toDouble() ?? 0,
      'orders_week': (week?['count'] as num?)?.toInt() ?? 0,
      'revenue_week': (week?['revenue'] as num?)?.toDouble() ?? 0,
      'products_total': await countDocs('products'),
      'users_total': await countDocs('users'),
      'top_products': [
        for (final row in topProducts)
          {
            'product_id': row['_id'],
            'name': row['name'],
            'qty': (row['qty'] as num?)?.toInt() ?? 0,
            'revenue': (row['revenue'] as num?)?.toDouble() ?? 0,
          },
      ],
    };
  }
}
