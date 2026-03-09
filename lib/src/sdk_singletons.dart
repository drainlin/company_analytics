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

  void start(SingularConfig config) => Singular.start(config);

  void event(String eventName) => Singular.event(eventName);

  void eventWithArgs(String eventName, Map args) =>
      Singular.eventWithArgs(eventName, args);

  void customRevenueWithAttributes(
    String eventName,
    String currency,
    double amount,
    Map attributes,
  ) {
    Singular.customRevenueWithAttributes(
      eventName,
      currency,
      amount,
      attributes,
    );
  }

  void setCustomUserId(String customUserId) =>
      Singular.setCustomUserId(customUserId);

  void unsetCustomUserId() => Singular.unsetCustomUserId();
}
