import 'package:facebook_app_events/facebook_app_events.dart';

import '../analytics_event.dart';
import '../analytics_provider.dart';
import '../sdk_singletons.dart';

class FacebookAnalyticsProvider implements AnalyticsProvider {
  FacebookAnalyticsProvider({
    FacebookAppEvents? appEvents,
    this.autoLogAppEventsEnabled,
    this.advertiserTrackingEnabled,
  }) : _appEvents =
           appEvents ?? AnalyticsSdkSingletons.facebookAppEventsInternal;

  final FacebookAppEvents _appEvents;
  final bool? autoLogAppEventsEnabled;
  final bool? advertiserTrackingEnabled;

  @override
  String get name => 'facebook_app_events';

  @override
  Future<void> initialize() async {
    if (autoLogAppEventsEnabled != null) {
      await _appEvents.setAutoLogAppEventsEnabled(autoLogAppEventsEnabled!);
    }

    if (advertiserTrackingEnabled != null) {
      await _appEvents.setAdvertiserTracking(
        enabled: advertiserTrackingEnabled!,
      );
    }
  }

  @override
  Future<void> track(AnalyticsEvent event) {
    return _appEvents.logEvent(
      name: event.name,
      parameters: event.parameters,
      valueToSum: event.valueToSum,
    );
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
