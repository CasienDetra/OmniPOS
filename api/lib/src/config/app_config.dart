import 'package:dotenv/dotenv.dart';

/// PayWay's sandbox host. Production is a different host with different keys,
/// so the base URL is configuration rather than a guess.
const String paywaySandboxBaseUrl = 'https://checkout-sandbox.payway.com.kh';

/// CutLuy's API host. It has no separate sandbox: a key for a test store on
/// the same host is what stands in for one.
const String cutluyProductionBaseUrl = 'https://cutluy.com';

/// The gateway the payment routes talk to when `PAYMENT_PROVIDER` says nothing.
const String defaultPaymentProviderName = 'cutluy';

class AppConfig {
  const AppConfig({
    required this.mongoUri,
    required this.port,
    required this.jwtSecret,
    required this.fileBaseUrl,
    required this.paywayBaseUrl,
    required this.paywayMerchantId,
    required this.paywayApiKey,
    required this.paywayCurrency,
    required this.paywayQrLifetime,
    required this.paywayCallbackUrl,
    required this.paywayQrImageTemplate,
    this.paymentProvider = defaultPaymentProviderName,
    this.cutluyBaseUrl = cutluyProductionBaseUrl,
    this.cutluyApiKey = '',
    this.cutluyWebhookSecret = '',
    this.cutluyWebhookTolerance = const Duration(minutes: 5),
    this.cutluyShopCurrency = 'KHR',
    this.cutluyKhrUsdRate = 0,
    this.cutluyFallbackExpiry = const Duration(minutes: 5),
  });

  static AppConfig? _current;
  static AppConfig get current => _current ??= AppConfig.fromEnvironment();

  final String mongoUri;
  final int port;
  final String jwtSecret;
  final String fileBaseUrl;

  /// `cutluy` or `payway`: which gateway the payment routes drive. One set of
  /// routes and one state machine, with the choice made by configuration
  /// instead of by editing code.
  final String paymentProvider;

  final String paywayBaseUrl;
  final String paywayMerchantId;
  final String paywayApiKey;

  /// `KHR` or `USD` — the only currencies PayWay accepts.
  final String paywayCurrency;

  /// How long a displayed QR stays payable.
  final Duration paywayQrLifetime;

  /// The URL PayWay posts payment notifications to. Empty means the service
  /// polls the Check-transaction API instead, which works on a laptop with no
  /// public address.
  final String paywayCallbackUrl;

  /// PayWay's branded QR image variant. Empty asks for the plain code; the
  /// cashier UI renders `qrString` itself either way.
  final String paywayQrImageTemplate;

  final String cutluyBaseUrl;

  /// The store's API key. Sent as `Authorization: Bearer`; it is the only
  /// credential CutLuy's payment API reads, and on its own it says which store
  /// and which payment link the money lands in.
  final String cutluyApiKey;

  /// The endpoint secret CutLuy signs its webhooks with. Empty means this
  /// deployment accepts no notification at all, which is the right answer for a
  /// machine CutLuy cannot reach: polling still closes sales.
  final String cutluyWebhookSecret;

  /// How far a delivery's timestamp may stray from this clock before the
  /// delivery is refused as a replay.
  final Duration cutluyWebhookTolerance;

  /// The currency the shelf prices are in. CutLuy charges USD, so a KHR shop
  /// has its cart converted before a code is asked for.
  final String cutluyShopCurrency;

  /// Riel per dollar, e.g. 4100. Zero means no rate was given, and a KHR shop
  /// cannot be charged in USD without one: guessing a rate would misbill every
  /// sale in the same direction.
  final double cutluyKhrUsdRate;

  /// How long a payment is treated as payable when the gateway's answer carries
  /// no expiry of its own.
  final Duration cutluyFallbackExpiry;

  /// Payments are unusable until the merchant id and API key arrive, and that
  /// has to be a visible 503 rather than a stack that will not start.
  bool get paywayConfigured =>
      paywayMerchantId.isNotEmpty && paywayApiKey.isNotEmpty;

  /// A key is enough to ask for money; a KHR shop also needs the rate that
  /// turns its prices into the dollars CutLuy charges.
  bool get cutluyConfigured =>
      cutluyApiKey.isNotEmpty &&
      (cutluyShopCurrency != 'KHR' || cutluyKhrUsdRate > 0);

  factory AppConfig.fromEnvironment() {
    final env = DotEnv(includePlatformEnvironment: true, quiet: true)
      ..load(['.env']);

    String read(String key, String fallback) {
      final value = env[key];
      return (value == null || value.isEmpty) ? fallback : value;
    }

    double readDouble(String key, double fallback) =>
        double.tryParse(read(key, '$fallback')) ?? fallback;

    final directUri = read('MONGODB_URI', '');
    final username = read('MONGO_USERNAME', '');
    final password = Uri.encodeComponent(read('MONGO_PASSWORD', ''));
    final auth = username.isEmpty ? '' : '$username:$password@';
    final mongoUri = directUri.isNotEmpty
        ? directUri
        : 'mongodb://$auth${read('MONGO_HOST', 'localhost')}:'
              '${read('MONGO_PORT', '27017')}/${read('MONGO_DATABASE', 'pos_api')}';

    return AppConfig(
      mongoUri: mongoUri,
      port: int.tryParse(read('PORT', '3000')) ?? 3000,
      jwtSecret: read('JWT_SECRET', 'change-me-in-production'),
      fileBaseUrl: read('FILE_BASE_URL', 'http://localhost:8080'),
      paymentProvider: read('PAYMENT_PROVIDER', defaultPaymentProviderName),
      paywayBaseUrl: read('PAYWAY_BASE_URL', paywaySandboxBaseUrl),
      paywayMerchantId: read('PAYWAY_MERCHANT_ID', ''),
      paywayApiKey: read('PAYWAY_API_KEY', ''),
      paywayCurrency: read('PAYWAY_CURRENCY', 'KHR').toUpperCase(),
      paywayQrLifetime: Duration(
        minutes: int.tryParse(read('PAYWAY_QR_LIFETIME_MINUTES', '10')) ?? 10,
      ),
      paywayCallbackUrl: read('PAYWAY_CALLBACK_URL', ''),
      paywayQrImageTemplate: read('PAYWAY_QR_IMAGE_TEMPLATE', ''),
      cutluyBaseUrl: read('CUTLUY_BASE_URL', cutluyProductionBaseUrl),
      cutluyApiKey: read('CUTLUY_API_KEY', ''),
      cutluyWebhookSecret: read('CUTLUY_WEBHOOK_SECRET', ''),
      cutluyWebhookTolerance: Duration(
        seconds:
            int.tryParse(read('CUTLUY_WEBHOOK_TOLERANCE_SECONDS', '300')) ??
            300,
      ),
      cutluyShopCurrency: read('CUTLUY_SHOP_CURRENCY', 'KHR').toUpperCase(),
      cutluyKhrUsdRate: readDouble('CUTLUY_KHR_USD_RATE', 0),
      cutluyFallbackExpiry: Duration(
        seconds:
            int.tryParse(read('CUTLUY_FALLBACK_EXPIRY_SECONDS', '300')) ?? 300,
      ),
    );
  }
}
