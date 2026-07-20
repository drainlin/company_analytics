import 'package:flutter/foundation.dart';
import 'package:facebook_app_events/facebook_app_events.dart';

import '../analytics_event.dart';
import '../analytics_provider.dart';
import '../sdk_singletons.dart';

class FacebookAnalyticsProvider implements AnalyticsProvider {
  FacebookAnalyticsProvider({
    FacebookAppEvents? appEvents,
    this.appId,
    this.clientToken,
    this.autoLogAppEventsEnabled,
    this.advertiserTrackingEnabled,
    this.testModeEnabled = false,
  }) : _appEvents =
           appEvents ?? AnalyticsSdkSingletons.facebookAppEventsInternal;

  final FacebookAppEvents _appEvents;
  final String? appId;
  final String? clientToken;
  final bool? autoLogAppEventsEnabled;
  final bool? advertiserTrackingEnabled;
  final bool testModeEnabled;

  @override
  String get name => 'facebook_app_events';

  @override
  Future<void> initialize() async {
    final resolvedAppId = appId?.trim();
    final resolvedClientToken = clientToken?.trim();
    if (resolvedAppId == null ||
        resolvedAppId.isEmpty ||
        resolvedClientToken == null ||
        resolvedClientToken.isEmpty) {
      throw StateError(
        'Facebook app id and client token are required before initializing Facebook analytics.',
      );
    }

    await _appEvents.configure(
      appId: resolvedAppId,
      clientToken: resolvedClientToken,
      autoLogAppEventsEnabled: autoLogAppEventsEnabled,
      advertiserIdCollectionEnabled: advertiserTrackingEnabled,
    );

    if (testModeEnabled) {
      await _appEvents.setDebugLoggingEnabled(true);
    }

    if (testModeEnabled) {
      debugPrint('Facebook test mode initialized. appId=$resolvedAppId');
    }
  }

  @override
  Future<void> track(AnalyticsEvent event) async {
    event.validate();
    if (_FacebookEventMapping.purchaseEvents.contains(event.name) &&
        !event.hasRevenue) {
      throw const AnalyticsEventValidationException(
        'Facebook purchase events require valueToSum and revenueCurrency.',
      );
    }
    final parameters = <String, dynamic>{...event.parameters};
    if (event.hasRevenue &&
        !parameters.containsKey(FacebookAppEvents.paramNameCurrency)) {
      parameters[FacebookAppEvents.paramNameCurrency] = event.revenueCurrency!;
    }

    if (_FacebookEventMapping.purchaseEvents.contains(event.name) &&
        event.hasRevenue) {
      await _appEvents.logPurchase(
        amount: event.valueToSum!,
        currency: event.revenueCurrency!,
        parameters: parameters..remove(FacebookAppEvents.paramNameCurrency),
      );
    } else {
      await _appEvents.logEvent(
        name: _FacebookEventMapping.names[event.name] ?? event.name,
        parameters: parameters,
        valueToSum: event.valueToSum,
      );
    }

    if (testModeEnabled) {
      await _appEvents.flush();
    }
  }

  @override
  Future<void> setUserId(String userId) {
    return _appEvents.setUserID(userId);
  }

  @override
  Future<void> clearUser() async {
    await _appEvents.clearUserID();
    await _appEvents.clearUserData();
  }
}

abstract final class _FacebookEventMapping {
  static const Set<String> purchaseEvents = <String>{
    'purchase',
    'purchase_success',
  };

  static const Map<String, String> names = <String, String>{
    'sign_up': FacebookAppEvents.eventNameCompletedRegistration,
    'view_content': FacebookAppEvents.eventNameViewedContent,
    'rate': FacebookAppEvents.eventNameRated,
    'begin_checkout': FacebookAppEvents.eventNameInitiatedCheckout,
    'add_to_cart': FacebookAppEvents.eventNameAddedToCart,
    'add_to_wishlist': FacebookAppEvents.eventNameAddedToWishlist,
    'subscribe': FacebookAppEvents.eventNameSubscribe,
    'start_trial': FacebookAppEvents.eventNameStartTrial,
    'ad_impression': FacebookAppEvents.eventNameAdImpression,
    'ad_click': FacebookAppEvents.eventNameAdClick,
    'level_achieved': FacebookAppEvents.eventNameAchievedLevel,
    'add_payment_info': FacebookAppEvents.eventNameAddedPaymentInfo,
    'tutorial_complete': FacebookAppEvents.eventNameCompletedTutorial,
    'search': FacebookAppEvents.eventNameSearched,
    'spend_virtual_currency': FacebookAppEvents.eventNameSpentCredits,
    'unlock_achievement': FacebookAppEvents.eventNameUnlockedAchievement,
  };
}
