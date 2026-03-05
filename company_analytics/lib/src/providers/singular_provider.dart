import 'package:singular_flutter_sdk/singular_config.dart';

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
      ..waitForTrackingAuthorizationWithTimeoutInterval =
          waitForTrackingAuthSeconds;

    _singular.start(config);
  }

  @override
  Future<void> track(AnalyticsEvent event) async {
    if (event.parameters.isEmpty) {
      _singular.event(event.name);
      return;
    }

    if (event.hasRevenue) {
      _singular.customRevenueWithAttributes(
        event.name,
        event.revenueCurrency!,
        event.valueToSum!,
        event.parameters,
      );
      return;
    }

    _singular.eventWithArgs(event.name, event.parameters);
  }

  @override
  Future<void> setUserId(String userId) async {
    _singular.setCustomUserId(userId);
  }

  @override
  Future<void> clearUser() async {
    _singular.unsetCustomUserId();
  }
}
