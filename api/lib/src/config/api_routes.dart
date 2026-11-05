/// The public URL space of the api service, in one place.
///
/// `routes/api/<apiVersionSegment>/...` is what dart_frog turns into these
/// paths, the auth guard matches on them, and the OpenAPI document lists
/// them. `test/unit/api_routes_test.dart` compares all three, so a version
/// bump that misses one of them fails the suite instead of quietly leaving a
/// guard that matches nothing.
const String apiVersionSegment = 'v1';

/// Prefix every versioned endpoint lives under.
const String apiPrefix = '/api/$apiVersionSegment';

/// First path segment for Admin-only endpoints; it is also the directory name
/// under `routes/api/<version>/`.
const String adminSection = 'admin';

/// First path segment for Cashier-only endpoints, same directory rule.
const String cashierSection = 'cashier';

const String adminPrefix = '$apiPrefix/$adminSection';

const String cashierPrefix = '$apiPrefix/$cashierSection';

/// Login issues the token that protects everything else, so it stays public.
const String loginPath = '$apiPrefix/account/auth/login';

/// Development-only endpoints that stay reachable without a token.
const String testingPrefix = '$apiPrefix/testing';

/// First path segment for payment endpoints. Unlike the two role sections it
/// belongs to neither Admin nor Cashier: the path holds the gateway's
/// notification endpoint, which arrives from a payments company and can never
/// carry our token.
const String paymentsSection = 'payments';

const String paymentsPrefix = '$apiPrefix/$paymentsSection';

/// Where the payment gateway posts "this QR has been paid", and the one route
/// that answers without a bearer token.
const String paymentCallbackPath = '$paymentsPrefix/callback';

/// Path prefixes that do not require a bearer token.
const List<String> publicApiPrefixes = [
  loginPath,
  testingPrefix,
  paymentCallbackPath,
];
