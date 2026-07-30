import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:singular_flutter_sdk/singular_ad_data.dart';
import 'package:singular_flutter_sdk/singular_config.dart';
import 'package:singular_flutter_sdk/singular_iap.dart';

const ADMON_REVENUE_EVENT_NAME = '__ADMON_USER_LEVEL_REVENUE__';
const _SDK_NAME = 'Flutter';
const _SDK_VERSION = '1.8.0';

typedef void ShortLinkCallback(String? data, String? error);

class Singular {
  static const MethodChannel _channel = const MethodChannel('singular-api');
  static SingularConfig? singularConfig;

  static Future<void> start(SingularConfig config) async {
    singularConfig = config;
    _setWrapperNameAndVersion(_SDK_NAME, _SDK_VERSION);
    await _channel.invokeMethod<void>('start', config.toMap);
  }

  static Future<void> event(String eventName) {
    return _channel.invokeMethod<void>('event', {'eventName': eventName});
  }

  static Future<void> eventWithArgs(String eventName, Map args) {
    return _channel.invokeMethod<void>('eventWithArgs', {
      'eventName': eventName,
      'args': args,
    });
  }

  static Future<void> setCustomUserId(String customUserId) {
    return _channel.invokeMethod<void>('setCustomUserId', {
      'customUserId': customUserId,
    });
  }

  static Future<void> unsetCustomUserId() {
    return _channel.invokeMethod<void>('unsetCustomUserId');
  }

  static void setDeviceCustomUserId(String customUserId) {
    _channel.invokeMethod('setDeviceCustomUserId', {
      'customUserId': customUserId,
    });
  }

  static void registerDeviceTokenForUninstall(String deviceToken) {
    _channel.invokeMethod('registerDeviceTokenForUninstall', {
      'deviceToken': deviceToken,
    });
  }

  static void setFCMDeviceToken(String fcmToken) {
    _channel.invokeMethod('setFCMDeviceToken', {'fcmToken': fcmToken});
  }

  // REVENUE

  static Future<void> customRevenue(
    String eventName,
    String currency,
    double amount,
  ) {
    return _channel.invokeMethod<void>('customRevenue', {
      'eventName': eventName,
      'currency': currency,
      'amount': amount,
    });
  }

  static Future<void> customRevenueWithAttributes(
    String eventName,
    String currency,
    double amount,
    Map attributes,
  ) {
    return _channel.invokeMethod<void>('customRevenueWithAttributes', {
      'eventName': eventName,
      'currency': currency,
      'amount': amount,
      'attributes': attributes,
    });
  }

  static void customRevenueWithAllAttributes(
    String eventName,
    String currency,
    double amount,
    String productSKU,
    String productName,
    String productCategory,
    int productQuantity,
    double productPrice,
  ) {
    _channel.invokeMethod('customRevenueWithAllAttributes', {
      'eventName': eventName,
      'currency': currency,
      'amount': amount,
      'productSKU': productSKU,
      'productName': productName,
      'productCategory': productCategory,
      'productQuantity': productQuantity,
      'productPrice': productPrice,
    });
  }

  static void _setWrapperNameAndVersion(String name, String version) {
    _channel.invokeMethod('setWrapperNameAndVersion', {
      'name': name,
      'version': version,
    });
  }

  /* Global Properties */

  static Future<Map> getGlobalProperties() async {
    final Map globalProperties = await _channel.invokeMethod(
      'getGlobalProperties',
    );
    return globalProperties;
  }

  static Future<bool> setGlobalProperty(
    String key,
    String value,
    bool overrideExisting,
  ) async {
    final bool isGlobalPropertySet = await _channel.invokeMethod(
      'setGlobalProperty',
      {'key': key, 'value': value, 'overrideExisting': overrideExisting},
    );
    return isGlobalPropertySet;
  }

  static void unsetGlobalProperty(String key) {
    _channel.invokeMethod('unsetGlobalProperty', {'key': key});
  }

  static void clearGlobalProperties() {
    _channel.invokeMethod('clearGlobalProperties');
  }

  /* GDPR helpers */

  static void trackingOptIn() {
    _channel.invokeMethod('trackingOptIn');
  }

  static void trackingUnder13() {
    _channel.invokeMethod('trackingUnder13');
  }

  static void stopAllTracking() {
    _channel.invokeMethod('stopAllTracking');
  }

  static void resumeAllTracking() {
    _channel.invokeMethod('resumeAllTracking');
  }

  static Future<bool> isAllTrackingStopped() async {
    final bool isTrackingStopped = await _channel.invokeMethod(
      'isAllTrackingStopped',
    );
    return isTrackingStopped;
  }

  static void limitDataSharing(bool shouldLimitDataSharing) {
    _channel.invokeMethod('limitDataSharing', {
      'limitDataSharing': shouldLimitDataSharing,
    });
  }

  static Future<bool> getLimitDataSharing() async {
    final bool isLimitDataSharing = await _channel.invokeMethod(
      'getLimitDataSharing',
    );
    return isLimitDataSharing;
  }

  /* SKAN Methods */

  static void skanRegisterAppForAdNetworkAttribution() {
    if (Platform.isIOS) {
      _channel.invokeMethod('skanRegisterAppForAdNetworkAttribution');
    }
  }

  static Future<bool> skanUpdateConversionValue(int conversionValue) async {
    if (Platform.isIOS) {
      final bool isConversionValueUpdated = await _channel.invokeMethod(
        'skanUpdateConversionValue',
        {'conversionValue': conversionValue},
      );
      return isConversionValueUpdated;
    }

    return false;
  }

  static void skanUpdateConversionValues(
    int conversionValue,
    int coarse,
    bool lock,
  ) {
    if (Platform.isIOS) {
      _channel.invokeMethod('skanUpdateConversionValues', {
        'conversionValue': conversionValue,
        'coarse': coarse,
        'lock': lock,
      });
    }
  }

  static Future<num> skanGetConversionValue() async {
    if (Platform.isIOS) {
      final num conversionValue = await _channel.invokeMethod(
        'skanUpdateConversionValue',
      );
      return conversionValue;
    }

    return -1;
  }

  /* IAP Methods */
  static Future<void> inAppPurchase(String eventName, SingularIAP purchase) {
    return _channel.invokeMethod<void>('eventWithArgs', {
      'eventName': eventName,
      'args': purchase.toMap,
    });
  }

  static Future<void> inAppPurchaseWithAttributes(
    String eventName,
    SingularIAP purchase,
    Map attributes,
  ) {
    return _channel.invokeMethod<void>('eventWithArgs', {
      'eventName': eventName,
      'args': {...attributes, ...purchase.toMap},
    });
  }

  static void adRevenue(SingularAdData? adData) {
    if (adData == null || !adData.hasRequiredParams()) {
      return;
    }
    _channel.invokeMethod('eventWithArgs', {
      'eventName': ADMON_REVENUE_EVENT_NAME,
      'args': adData,
    });
  }

  static void createReferrerShortLink(
    String baseLink,
    String referrerName,
    String referrerId,
    Map args,
    ShortLinkCallback shortLinkCallback,
  ) {
    _channel.invokeMethod('createReferrerShortLink', {
      'baseLink': baseLink,
      'referrerName': referrerName,
      'referrerId': referrerId,
      'args': args,
    });

    singularConfig?.setShortLinkCallback(shortLinkCallback);
  }

  static void handlePushNotification(Map pushNotificationPayload) {
    if (Platform.isIOS) {
      _channel.invokeMethod('handlePushNotification', {
        'pushNotificationPayload': pushNotificationPayload,
      });
    }
  }

  static void setLimitAdvertisingIdentifiers(bool enabled) {
    _channel.invokeMethod('setLimitAdvertisingIdentifiers', {
      'limitAdvertisingIdentifiers': enabled,
    });
  }
}
