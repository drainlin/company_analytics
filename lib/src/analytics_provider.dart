import 'analytics_event.dart';

/// A destination that can receive analytics lifecycle and tracking calls.
abstract class AnalyticsProvider {
  /// Stable provider name used for diagnostics.
  String get name;

  /// Prepares the provider before events are sent.
  Future<void> initialize();

  /// Sends one analytics event to this provider.
  Future<void> track(AnalyticsEvent event);

  /// Associates subsequent events with a user id.
  Future<void> setUserId(String userId);

  /// Clears user identity from this provider.
  Future<void> clearUser();
}
