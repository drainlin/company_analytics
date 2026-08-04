import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:singular_flutter_sdk/events.dart';
import 'package:singular_flutter_sdk/singular_config.dart';
import 'package:singular_flutter_sdk/singular_iap.dart';

import '../analytics_event.dart';
import '../analytics_provider.dart';
import '../sdk_singletons.dart';

class SingularAnalyticsProvider implements AnalyticsProvider {
  SingularAnalyticsProvider({
    required this.apiKey,
    required this.secret,
    required this.enableLogging,
    required this.waitForTrackingAuthSeconds,
    SingularSdkFacade? singular,
  }) : _singular = singular ?? AnalyticsSdkSingletons.singularInternal;

  final String apiKey;
  final String secret;
  final bool enableLogging;
  final int waitForTrackingAuthSeconds;
  final SingularSdkFacade _singular;

  @override
  String get name => 'singular_flutter_sdk';

  @override
  Future<void> initialize() async {
    final config = SingularConfig(apiKey, secret)
      ..enableLogging = enableLogging
      ..logLevel = enableLogging ? 5 : -1
      ..waitForTrackingAuthorizationWithTimeoutInterval =
          waitForTrackingAuthSeconds;

    _log(
      'initialize enableLogging=$enableLogging '
      'logLevel=${config.logLevel} waitForATT=$waitForTrackingAuthSeconds',
    );
    await _singular.start(config);
    _log('initialize completed');
  }

  @override
  Future<void> track(AnalyticsEvent event) async {
    if (event.hasRevenue) {
      if (event.parameters.isEmpty) {
        await _singular.customRevenue(
          event.name,
          event.revenueCurrency!,
          event.valueToSum!,
        );
        return;
      }

      await _singular.customRevenueWithAttributes(
        event.name,
        event.revenueCurrency!,
        event.valueToSum!,
        event.parameters,
      );
      return;
    }

    if (event.parameters.isEmpty) {
      await _singular.event(event.name);
      return;
    }

    await _singular.eventWithArgs(event.name, event.parameters);
  }

  /// Reports a new non-subscription store purchase with validation data.
  Future<void> trackInAppPurchase(
    PurchaseDetails purchase,
    ProductDetails product, {
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) async {
    if (purchase.status != PurchaseStatus.purchased) {
      throw const AnalyticsEventValidationException(
        'Only newly purchased in-app purchases can be reported to Singular.',
      );
    }
    if (purchase.productID != product.id) {
      throw const AnalyticsEventValidationException(
        'Purchase product id must match ProductDetails.id.',
      );
    }
    if (!product.rawPrice.isFinite || product.rawPrice <= 0) {
      throw const AnalyticsEventValidationException(
        'In-app purchase price must be finite and greater than zero.',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(product.currencyCode)) {
      throw const AnalyticsEventValidationException(
        'In-app purchase currency must be a three-letter uppercase '
        'ISO 4217 code.',
      );
    }

    _log(
      'IAP received type=${purchase.runtimeType} product=${purchase.productID} '
      'transaction=${purchase.purchaseID ?? 'null'} '
      'receiptLength=${purchase.verificationData.serverVerificationData.length} '
      'amount=${product.rawPrice} currency=${product.currencyCode}',
    );

    if (purchase is AppStorePurchaseDetails) {
      final transactionId = purchase.purchaseID?.trim();
      if (transactionId == null || transactionId.isEmpty) {
        throw const AnalyticsEventValidationException(
          'StoreKit 1 purchases require a transaction id.',
        );
      }
      _log(
        'routing StoreKit 1 purchase through native '
        'Singular validated transaction revenue path',
      );
      await _singular.storeKit1InAppPurchase(
        Events.sngEcommercePurchase,
        transactionId: transactionId,
        productId: purchase.productID,
        amount: product.rawPrice,
        currency: product.currencyCode,
        attributes: attributes,
      );
      _log('native StoreKit 1 IAP call completed');
      return;
    }

    final singularPurchase = _buildSingularPurchase(purchase, product);
    _log('routing purchase through Singular receipt/JWS event path');
    if (attributes.isEmpty) {
      await _singular.inAppPurchase(
        Events.sngEcommercePurchase,
        singularPurchase,
      );
      return;
    }
    await _singular.inAppPurchaseWithAttributes(
      Events.sngEcommercePurchase,
      singularPurchase,
      attributes,
    );
  }

  void _log(String message) {
    if (enableLogging) {
      // Never log the API secret or receipt body.
      // ignore: avoid_print
      print('[company_analytics][Singular] $message');
    }
  }

  static SingularIAP _buildSingularPurchase(
    PurchaseDetails purchase,
    ProductDetails product,
  ) {
    switch (purchase.verificationData.source) {
      case 'google_play':
        if (purchase is! GooglePlayPurchaseDetails) {
          throw const AnalyticsEventValidationException(
            'Google Play purchases must be GooglePlayPurchaseDetails.',
          );
        }
        return SingularAndroidIAP(
          product.rawPrice,
          product.currencyCode,
          purchase.billingClientPurchase.signature,
          purchase.billingClientPurchase.originalJson,
        );
      case 'app_store':
        return SingularIOSIAP(
          product.rawPrice,
          product.currencyCode,
          purchase.productID,
          purchase.purchaseID,
          purchase.verificationData.serverVerificationData,
        );
      default:
        throw AnalyticsEventValidationException(
          'Unsupported in-app purchase source: '
          '${purchase.verificationData.source}.',
        );
    }
  }

  @override
  Future<void> setUserId(String userId) async {
    await _singular.setCustomUserId(userId);
  }

  @override
  Future<void> clearUser() async {
    await _singular.unsetCustomUserId();
  }
}
