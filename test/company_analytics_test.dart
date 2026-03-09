import 'package:company_analytics/company_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CompanyAnalytics', () {
    test('queues events before init and flushes after init', () async {
      final provider = InMemoryAnalyticsProvider();
      final analytics = CompanyAnalytics(
        providers: <InMemoryAnalyticsProvider>[provider],
      );

      await analytics.track(const AnalyticsEvent(name: 'app_open'));

      await analytics.init(
        const AnalyticsConfig(
          singularApiKey: 'fake_key',
          singularSecret: 'fake_secret',
          enableFacebook: false,
          enableSingular: false,
        ),
      );

      expect(provider.trackedEvents.length, 1);
      expect(provider.trackedEvents.first.name, 'app_open');
    });

    test('throws before init when failFastBeforeInit is true', () async {
      final analytics = CompanyAnalytics(failFastBeforeInit: true);

      expect(
        () => analytics.track(const AnalyticsEvent(name: 'purchase')),
        throwsA(isA<AnalyticsNotInitializedException>()),
      );
    });

    test('validates config', () {
      final analytics = CompanyAnalytics();

      expect(
        () => analytics.init(
          const AnalyticsConfig(
            singularApiKey: '',
            singularSecret: '',
            enableFacebook: false,
            enableSingular: true,
          ),
        ),
        throwsA(isA<AnalyticsInitializationException>()),
      );
    });
  });

  group('AnalyticsSdkSingletons', () {
    test('returns stable singleton instances', () {
      final fb1 = AnalyticsSdkSingletons.facebookAppEvents;
      final fb2 = AnalyticsSdkSingletons.facebookAppEvents;
      final s1 = AnalyticsSdkSingletons.singular;
      final s2 = AnalyticsSdkSingletons.singular;

      expect(identical(fb1, fb2), isTrue);
      expect(identical(s1, s2), isTrue);
    });
  });
}
