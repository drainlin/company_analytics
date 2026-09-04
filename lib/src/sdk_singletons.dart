import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:singular_flutter_sdk/singular.dart';
import 'package:singular_flutter_sdk/singular_config.dart';

/// Exposes raw SDK singletons for edge cases.
///
/// Prefer using [CompanyAnalytics] for normal tracking flow.
class AnalyticsSdkSingletons {
  static final FacebookAppEvents _facebookAppEvents = FacebookAppEvents();
  static final SingularSdkFacade _singular = SingularSdkFacade._();

  @Deprecated(
    'Avoid direct Facebook SDK calls in feature code. Use CompanyAnalytics when possible.',
  )
  static FacebookAppEvents get facebookAppEvents {
    return _facebookAppEvents;
  }

  @Deprecated(
    'Avoid direct Singular SDK calls in feature code. Use CompanyAnalytics when possible.',
  )
  static SingularSdkFacade get singular {
    return _singular;
  }

  static FacebookAppEvents get facebookAppEventsInternal => _facebookAppEvents;

  static SingularSdkFacade get singularInternal => _singular;
}

/// Small instance facade over Singular static SDK to support singleton exposure.
class SingularSdkFacade {
  SingularSdkFacade._();

  Future<void> start(SingularConfig config) => Singular.start(config);

  Future<void> event(String eventName) => Singular.event(eventName);

  Future<void> eventWithArgs(String eventName, Map args) =>
      Singular.eventWithArgs(eventName, args);

  Future<void> customRevenue(String eventName, String currency, double amount) {
    return Singular.customRevenue(eventName, currency, amount);
  }

  Future<void> customRevenueWithAttributes(
    String eventName,
    String currency,
    double amount,
    Map attributes,
  ) {
    return Singular.customRevenueWithAttributes(
      eventName,
      currency,
      amount,
      attributes,
    );
  }

  Future<void> setCustomUserId(String customUserId) =>
      Singular.setCustomUserId(customUserId);

  Future<void> unsetCustomUserId() => Singular.unsetCustomUserId();
}
