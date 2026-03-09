import 'analytics_event.dart';

abstract class AnalyticsProvider {
  String get name;

  Future<void> initialize();

  Future<void> track(AnalyticsEvent event);

  Future<void> setUserId(String userId);

  Future<void> clearUser();
}
