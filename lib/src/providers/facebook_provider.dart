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
  }) : _appEvents =
           appEvents ?? AnalyticsSdkSingletons.facebookAppEventsInternal;

  final FacebookAppEvents _appEvents;
  final String? appId;
  final String? clientToken;
  final bool? autoLogAppEventsEnabled;
  final bool? advertiserTrackingEnabled;

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
    );

    if (autoLogAppEventsEnabled != null) {
      await _appEvents.setAutoLogAppEventsEnabled(autoLogAppEventsEnabled!);
    }

    if (advertiserTrackingEnabled != null) {
      await _appEvents.setAdvertiserIdCollectionEnabled(
        advertiserTrackingEnabled!,
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
