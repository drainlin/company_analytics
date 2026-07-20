import 'dart:async';
import 'dart:convert';

import 'package:company_analytics/company_analytics.dart';
import 'package:company_analytics/src/providers/facebook_provider.dart';
import 'package:company_analytics/src/providers/singular_provider.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singular_flutter_sdk/singular.dart';
import 'package:singular_flutter_sdk/singular_config.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('CompanyAnalytics', () {
    test('queues events before init and flushes after init', () async {
      final provider = InMemoryAnalyticsProvider();
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );
      final analytics = CompanyAnalytics(
        providers: <InMemoryAnalyticsProvider>[provider],
        trackingAuthorizationRequester:
            _RecordingTrackingAuthorizationRequester(<String>[]),
      );

      await analytics.track(const AnalyticsEvent(name: 'app_open'));

      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: loader,
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

    test('rejects incomplete revenue events before queueing', () async {
      final analytics = CompanyAnalytics();

      await expectLater(
        analytics.track(
          const AnalyticsEvent(name: 'purchase_success', valueToSum: 9.99),
        ),
        throwsA(isA<AnalyticsEventValidationException>()),
      );
    });

    test('validates remote singular config before native initialization', () {
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_invalidSingularRemoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );
      final analytics = CompanyAnalytics();

      expect(
        () => analytics.initFromRemoteConfig(
          RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
          loader: loader,
        ),
        throwsA(isA<AnalyticsInitializationException>()),
      );
    });

    test('validates facebook runtime config before native initialization', () {
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_invalidFacebookRemoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );
      final analytics = CompanyAnalytics();

      expect(
        () => analytics.initFromRemoteConfig(
          RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
          loader: loader,
        ),
        throwsA(isA<AnalyticsInitializationException>()),
      );
    });

    test('initFromRemoteConfig initializes from fetched json', () async {
      final provider = InMemoryAnalyticsProvider();
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );
      final analytics = CompanyAnalytics(
        providers: <InMemoryAnalyticsProvider>[provider],
      );

      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: loader,
      );

      expect(analytics.isInitialized, isTrue);
      expect(
        analytics.lastRemoteConfigResult?.source,
        RemoteAnalyticsConfigSource.remote,
      );
    });

    test(
      'initFromRemoteConfig treats default placeholder json as no-op',
      () async {
        final requester = _RecordingTrackingAuthorizationRequester(<String>[]);
        final loader = RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.iOS,
        );
        final analytics = CompanyAnalytics(
          trackingAuthorizationRequester: requester,
        );

        await analytics.initFromRemoteConfig(
          RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
          loader: loader,
        );
        await analytics.track(const AnalyticsEvent(name: 'app_open'));

        expect(analytics.isInitialized, isTrue);
        expect(requester.requestCount, 1);
        expect(
          analytics.lastRemoteConfigResult?.config.enableFacebook,
          isFalse,
        );
        expect(
          analytics.lastRemoteConfigResult?.config.enableSingular,
          isFalse,
        );
      },
    );

    test('requests ATT after config load and before provider init', () async {
      final order = <String>[];
      final provider = _OrderingAnalyticsProvider(order);
      final requester = _RecordingTrackingAuthorizationRequester(order);
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );
      final analytics = CompanyAnalytics(
        providers: <InMemoryAnalyticsProvider>[provider],
        trackingAuthorizationRequester: requester,
      );

      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: loader,
      );

      expect(requester.requestCount, 1);
      expect(order, <String>['att', 'provider']);
    });

    test(
      'track retries failed remote init and sends event after success',
      () async {
        final provider = InMemoryAnalyticsProvider();
        final httpClient = _SequenceConfigHttpClient(<Object>[
          Exception('network down'),
          _remoteJson,
        ]);
        final loader = RemoteAnalyticsConfigLoader(
          httpClient: httpClient,
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.iOS,
        );
        final analytics = CompanyAnalytics(
          providers: <InMemoryAnalyticsProvider>[provider],
        );
        final remoteConfig = RemoteAnalyticsConfig(
          url: Uri.parse('http://127.0.0.1/config.json'),
          maxAttempts: 1,
        );

        await expectLater(
          analytics.initFromRemoteConfig(remoteConfig, loader: loader),
          throwsA(isA<AnalyticsInitializationException>()),
        );

        await analytics.track(const AnalyticsEvent(name: 'app_open'));

        expect(analytics.isInitialized, isTrue);
        expect(httpClient.callCount, 2);
        expect(provider.trackedEvents.map((event) => event.name), <String>[
          'app_open',
        ]);
      },
    );

    test(
      'track waits for in-flight remote init without duplicate fetch',
      () async {
        final provider = InMemoryAnalyticsProvider();
        final completer = Completer<String>();
        final httpClient = _CompleterConfigHttpClient(completer.future);
        final loader = RemoteAnalyticsConfigLoader(
          httpClient: httpClient,
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.iOS,
        );
        final analytics = CompanyAnalytics(
          providers: <InMemoryAnalyticsProvider>[provider],
        );
        final remoteConfig = RemoteAnalyticsConfig(
          url: Uri.parse('http://127.0.0.1/config.json'),
        );

        final initFuture = analytics.initFromRemoteConfig(
          remoteConfig,
          loader: loader,
        );
        await Future<void>.delayed(Duration.zero);

        final trackFuture = analytics.track(
          const AnalyticsEvent(name: 'app_open'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(httpClient.callCount, 1);

        completer.complete(_remoteJson);
        await initFuture;
        await trackFuture;

        expect(analytics.isInitialized, isTrue);
        expect(httpClient.callCount, 1);
        expect(provider.trackedEvents.map((event) => event.name), <String>[
          'app_open',
        ]);
      },
    );

    test('continues delivering when one provider fails', () async {
      final failing = _FailingAnalyticsProvider();
      final recording = InMemoryAnalyticsProvider();
      final analytics = CompanyAnalytics(
        providers: <AnalyticsProvider>[failing, recording],
        trackingAuthorizationRequester:
            _RecordingTrackingAuthorizationRequester(<String>[]),
      );

      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.android,
        ),
      );

      await expectLater(
        analytics.track(const AnalyticsEvent(name: 'view_home')),
        throwsA(isA<AnalyticsDeliveryException>()),
      );
      expect(recording.trackedEvents.single.name, 'view_home');
    });

    test('keeps a queued event until a retry succeeds', () async {
      final provider = _FailOnceAnalyticsProvider();
      final analytics = CompanyAnalytics(
        providers: <AnalyticsProvider>[provider],
        trackingAuthorizationRequester:
            _RecordingTrackingAuthorizationRequester(<String>[]),
      );

      await analytics.track(const AnalyticsEvent(name: 'queued_event'));
      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.android,
        ),
      );
      await analytics.track(const AnalyticsEvent(name: 'current_event'));

      expect(provider.successfulEvents, <String>[
        'queued_event',
        'current_event',
      ]);
    });

    test('restores queued events after recreating the facade', () async {
      final first = CompanyAnalytics();
      await first.track(const AnalyticsEvent(name: 'persisted_event'));

      final provider = InMemoryAnalyticsProvider();
      final second = CompanyAnalytics(
        providers: <AnalyticsProvider>[provider],
        trackingAuthorizationRequester:
            _RecordingTrackingAuthorizationRequester(<String>[]),
      );
      await second.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.android,
        ),
      );

      expect(provider.trackedEvents.single.name, 'persisted_event');
    });

    test('serializes concurrent persistent outbox writes', () async {
      final store = _BlockingFirstSaveEventStore();
      final analytics = CompanyAnalytics(eventStore: store);

      final first = analytics.track(const AnalyticsEvent(name: 'first'));
      await store.firstSaveStarted.future;
      final second = analytics.track(const AnalyticsEvent(name: 'second'));
      store.releaseFirstSave.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(store.events.map((event) => event.name), <String>[
        'first',
        'second',
      ]);
    });

    test('bounds the persistent outbox and drops the oldest event', () async {
      final store = _RecordingEventStore();
      final analytics = CompanyAnalytics(
        eventStore: store,
        maxPendingEvents: 3,
      );

      for (var index = 1; index <= 4; index += 1) {
        await analytics.track(AnalyticsEvent(name: 'event_$index'));
      }

      expect(analytics.droppedPendingEventCount, 1);
      expect(store.events.map((event) => event.name), <String>[
        'event_2',
        'event_3',
        'event_4',
      ]);
    });

    test('persists a successful outbox drain in one batch', () async {
      final store = _RecordingEventStore(
        events: <AnalyticsEvent>[
          const AnalyticsEvent(name: 'first'),
          const AnalyticsEvent(name: 'second'),
          const AnalyticsEvent(name: 'third'),
        ],
      );
      final provider = InMemoryAnalyticsProvider();
      final analytics = CompanyAnalytics(
        providers: <AnalyticsProvider>[provider],
        eventStore: store,
        trackingAuthorizationRequester:
            _RecordingTrackingAuthorizationRequester(<String>[]),
      );

      await analytics.initFromRemoteConfig(
        RemoteAnalyticsConfig(url: Uri.parse('http://127.0.0.1/config.json')),
        loader: RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
          cache: _MemoryConfigCache(),
          platform: TargetPlatform.android,
        ),
      );

      expect(provider.trackedEvents, hasLength(3));
      expect(store.events, isEmpty);
      expect(store.saveCount, 1);
    });
  });

  group('RemoteAnalyticsConfigLoader', () {
    test('uses a 15 second default timeout', () {
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
      );

      expect(remoteConfig.timeout, const Duration(seconds: 15));
    });

    test('parses unified remote config json', () {
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.android,
      );

      final config = loader.parse(_remoteJson);

      expect(config.facebookAppId, 'fb_app_android');
      expect(config.facebookClientToken, 'fb_token_android');
      expect(config.singularApiKey, 'singular_key_android');
      expect(config.singularSecret, 'singular_secret_android');
      expect(config.enableFacebook, isTrue);
      expect(config.enableSingular, isTrue);
      expect(config.facebookAutoLogAppEventsEnabled, isTrue);
      expect(config.facebookAdvertiserTrackingEnabled, isFalse);
      expect(config.singularEnableLogging, isTrue);
      expect(config.singularWaitForTrackingAuthSeconds, 15);
    });

    test('treats default placeholder values as disabled providers', () {
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_defaultRemoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.android,
      );

      final config = loader.parse(_defaultRemoteJson);

      expect(config.facebookAppId, 'YOUR_FACEBOOK_APP_ID_ANDROID');
      expect(config.facebookClientToken, 'YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID');
      expect(config.singularApiKey, 'YOUR_SINGULAR_API_KEY_ANDROID');
      expect(config.singularSecret, 'YOUR_SINGULAR_SECRET_ANDROID');
      expect(config.enableFacebook, isFalse);
      expect(config.enableSingular, isFalse);
      expect(config.validate(), isEmpty);
    });

    test('parses ios values from the same remote config json', () {
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.iOS,
      );

      final config = loader.parse(_remoteJson);

      expect(config.facebookAppId, 'fb_app_ios');
      expect(config.facebookClientToken, 'fb_token_ios');
      expect(config.singularApiKey, 'singular_key_ios');
      expect(config.singularSecret, 'singular_secret_ios');
    });

    test('writes successful remote config and metadata to cache', () async {
      final cache = _MemoryConfigCache();
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: cache,
        platform: TargetPlatform.iOS,
      );
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
      );

      final result = await loader.loadResult(remoteConfig);

      expect(result.changedFromCache, isFalse);
      expect(result.previousMetadata, isNull);
      expect(await cache.read(remoteConfig.cacheKey), _remoteJson);
      final metadata = RemoteAnalyticsConfigMetadata.tryParse(
        await cache.read('${remoteConfig.cacheKey}.metadata'),
      );
      expect(metadata, isNotNull);
      expect(metadata!.version, 1);
      expect(metadata.sourceUrl, 'http://127.0.0.1/config.json');
      expect(metadata.sha256, isNotEmpty);
    });

    test('uses cached config when remote fetch fails', () async {
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
      );
      final cache = _MemoryConfigCache()
        ..values[remoteConfig.cacheKey] = _remoteJson;
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FailingConfigHttpClient(),
        cache: cache,
        platform: TargetPlatform.android,
      );

      final result = await loader.loadResult(remoteConfig);
      final config = result.config;

      expect(result.source, RemoteAnalyticsConfigSource.cache);
      expect(config.facebookAppId, 'fb_app_android');
      expect(config.singularApiKey, 'singular_key_android');
    });

    test(
      'uses newly fetched facebook credentials from cache on the next launch',
      () async {
        final cache = _MemoryConfigCache();
        final remoteConfig = RemoteAnalyticsConfig(
          url: Uri.parse('http://127.0.0.1/config.json'),
          maxAttempts: 1,
        );
        final firstLaunchLoader = RemoteAnalyticsConfigLoader(
          httpClient: _FakeConfigHttpClient(_remoteJson),
          cache: cache,
          platform: TargetPlatform.android,
        );

        final fetched = await firstLaunchLoader.loadResult(remoteConfig);

        expect(fetched.source, RemoteAnalyticsConfigSource.remote);
        expect(fetched.config.facebookAppId, 'fb_app_android');

        final nextLaunchLoader = RemoteAnalyticsConfigLoader(
          httpClient: _FailingConfigHttpClient(),
          cache: cache,
          platform: TargetPlatform.android,
        );
        final restored = await nextLaunchLoader.loadResult(remoteConfig);

        expect(restored.source, RemoteAnalyticsConfigSource.cache);
        expect(restored.config.facebookAppId, 'fb_app_android');
        expect(restored.config.facebookClientToken, 'fb_token_android');
      },
    );

    test('retries remote fetch before using successful config', () async {
      final httpClient = _SequenceConfigHttpClient(<Object>[
        Exception('network down once'),
        Exception('network down twice'),
        _remoteJson,
      ]);
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: httpClient,
        cache: _MemoryConfigCache(),
        platform: TargetPlatform.android,
      );
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );

      final result = await loader.loadResult(remoteConfig);

      expect(result.source, RemoteAnalyticsConfigSource.remote);
      expect(result.config.facebookAppId, 'fb_app_android');
      expect(httpClient.callCount, 3);
    });

    test('reports when a fetched remote config differs from cache', () async {
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
      );
      final previousMetadata = RemoteAnalyticsConfigMetadata(
        sha256: 'old_sha',
        sourceUrl: remoteConfig.url.toString(),
        cachedAt: DateTime.utc(2026),
        version: 0,
      );
      final cache = _MemoryConfigCache()
        ..values[remoteConfig.cacheKey] = '{"old":true}'
        ..values['${remoteConfig.cacheKey}.metadata'] = jsonEncode(
          previousMetadata.toJson(),
        );
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: cache,
        platform: TargetPlatform.iOS,
      );

      final result = await loader.loadResult(remoteConfig);

      expect(result.source, RemoteAnalyticsConfigSource.remote);
      expect(result.changedFromCache, isTrue);
      expect(result.previousMetadata?.sha256, 'old_sha');
      expect(result.metadata?.sha256, isNot('old_sha'));
    });

    test('clears cached remote config and metadata', () async {
      final remoteConfig = RemoteAnalyticsConfig(
        url: Uri.parse('http://127.0.0.1/config.json'),
      );
      final cache = _MemoryConfigCache()
        ..values[remoteConfig.cacheKey] = _remoteJson
        ..values['${remoteConfig.cacheKey}.metadata'] = '{}';
      final loader = RemoteAnalyticsConfigLoader(
        httpClient: _FakeConfigHttpClient(_remoteJson),
        cache: cache,
        platform: TargetPlatform.iOS,
      );

      await loader.clearCache(remoteConfig);

      expect(await cache.read(remoteConfig.cacheKey), isNull);
      expect(await cache.read('${remoteConfig.cacheKey}.metadata'), isNull);
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

  group('FacebookAnalyticsProvider', () {
    test('requires runtime app id and client token before native setup', () {
      final provider = FacebookAnalyticsProvider();

      expect(provider.initialize(), throwsA(isA<StateError>()));
    });

    test('enables Facebook test mode during initialization', () async {
      final appEvents = _RecordingFacebookAppEvents();
      final provider = FacebookAnalyticsProvider(
        appEvents: appEvents,
        appId: 'fb_app',
        clientToken: 'fb_token',
        autoLogAppEventsEnabled: true,
        advertiserTrackingEnabled: false,
        testModeEnabled: true,
      );

      await provider.initialize();

      expect(appEvents.configuredAppId, 'fb_app');
      expect(appEvents.configuredClientToken, 'fb_token');
      expect(appEvents.configuredAutoLogAppEventsEnabled, isTrue);
      expect(appEvents.configuredAdvertiserIdCollectionEnabled, isFalse);
      expect(appEvents.debugLoggingEnabled, isTrue);
    });

    test('flushes Facebook events immediately in test mode', () async {
      final appEvents = _RecordingFacebookAppEvents();
      final provider = FacebookAnalyticsProvider(
        appEvents: appEvents,
        testModeEnabled: true,
      );

      await provider.track(const AnalyticsEvent(name: 'test_event'));

      expect(appEvents.lastName, 'test_event');
      expect(appEvents.flushCount, 1);
    });

    test('uses Facebook purchase API for purchase revenue events', () async {
      final appEvents = _RecordingFacebookAppEvents();
      final provider = FacebookAnalyticsProvider(appEvents: appEvents);

      await provider.track(
        const AnalyticsEvent(
          name: 'purchase_success',
          parameters: {'product_id': 'sub_monthly'},
          valueToSum: 9.99,
          revenueCurrency: 'USD',
        ),
      );

      expect(appEvents.lastName, isNull);
      expect(appEvents.lastPurchaseAmount, 9.99);
      expect(appEvents.lastPurchaseCurrency, 'USD');
      expect(appEvents.lastParameters, <String, dynamic>{
        'product_id': 'sub_monthly',
      });
    });

    test('rejects Facebook purchase events without revenue', () async {
      final provider = FacebookAnalyticsProvider(
        appEvents: _RecordingFacebookAppEvents(),
      );

      await expectLater(
        provider.track(const AnalyticsEvent(name: 'purchase_success')),
        throwsA(isA<AnalyticsEventValidationException>()),
      );
    });

    test('maps shared event names to Facebook standard events', () async {
      final appEvents = _RecordingFacebookAppEvents();
      final provider = FacebookAnalyticsProvider(appEvents: appEvents);

      await provider.track(const AnalyticsEvent(name: 'view_content'));

      expect(appEvents.lastName, FacebookAppEvents.eventNameViewedContent);
    });
  });

  group('SingularAnalyticsProvider', () {
    test('sends revenue without parameters as Singular revenue', () async {
      final singular = _RecordingSingularSdkFacade();
      final provider = SingularAnalyticsProvider(
        apiKey: 'key',
        secret: 'secret',
        enableLogging: false,
        waitForTrackingAuthSeconds: 0,
        singular: singular,
      );

      await provider.track(
        const AnalyticsEvent(
          name: 'purchase_success',
          valueToSum: 9.99,
          revenueCurrency: 'USD',
        ),
      );

      expect(singular.calls, <String>['customRevenue']);
      expect(singular.lastEventName, 'purchase_success');
      expect(singular.lastCurrency, 'USD');
      expect(singular.lastAmount, 9.99);
    });

    test(
      'sends revenue with parameters as Singular revenue attributes',
      () async {
        final singular = _RecordingSingularSdkFacade();
        final provider = SingularAnalyticsProvider(
          apiKey: 'key',
          secret: 'secret',
          enableLogging: false,
          waitForTrackingAuthSeconds: 0,
          singular: singular,
        );

        await provider.track(
          const AnalyticsEvent(
            name: 'purchase_success',
            parameters: {'product_id': 'sub_monthly'},
            valueToSum: 9.99,
            revenueCurrency: 'USD',
          ),
        );

        expect(singular.calls, <String>['customRevenueWithAttributes']);
        expect(singular.lastEventName, 'purchase_success');
        expect(singular.lastCurrency, 'USD');
        expect(singular.lastAmount, 9.99);
        expect(singular.lastArgs, <String, dynamic>{
          'product_id': 'sub_monthly',
        });
      },
    );

    test('sends ordinary events through non-revenue Singular APIs', () async {
      final singular = _RecordingSingularSdkFacade();
      final provider = SingularAnalyticsProvider(
        apiKey: 'key',
        secret: 'secret',
        enableLogging: false,
        waitForTrackingAuthSeconds: 0,
        singular: singular,
      );

      await provider.track(const AnalyticsEvent(name: 'app_open'));
      await provider.track(
        const AnalyticsEvent(name: 'view_home', parameters: {'source': 'tab'}),
      );

      expect(singular.calls, <String>['event', 'eventWithArgs']);
      expect(singular.lastEventName, 'view_home');
      expect(singular.lastArgs, <String, dynamic>{'source': 'tab'});
    });

    test('propagates Singular platform delivery errors', () async {
      final provider = SingularAnalyticsProvider(
        apiKey: 'key',
        secret: 'secret',
        enableLogging: false,
        waitForTrackingAuthSeconds: 0,
        singular: _FailingSingularSdkFacade(),
      );

      await expectLater(
        provider.track(const AnalyticsEvent(name: 'view_home')),
        throwsA(isA<StateError>()),
      );
    });

    test('observes Singular MethodChannel exceptions', () async {
      const channel = MethodChannel('singular-api');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'delivery_failed');
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      await expectLater(
        Singular.event('view_home'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'delivery_failed',
          ),
        ),
      );
    });
  });
}

const String _remoteJson = '''
{
  "version": 1,
  "enable_facebook": true,
  "enable_singular": true,
  "facebook": {
    "ios": {
      "app_id": "fb_app_ios",
      "client_token": "fb_token_ios"
    },
    "android": {
      "app_id": "fb_app_android",
      "client_token": "fb_token_android"
    },
    "auto_log_app_events_enabled": true,
    "advertiser_tracking_enabled": false
  },
  "singular": {
    "ios": {
      "api_key": "singular_key_ios",
      "secret": "singular_secret_ios"
    },
    "android": {
      "api_key": "singular_key_android",
      "secret": "singular_secret_android"
    },
    "enable_logging": true,
    "wait_for_tracking_auth_seconds": 15
  }
}
''';

const String _defaultRemoteJson = '''
{
  "version": 1,
  "enable_facebook": true,
  "enable_singular": true,
  "facebook": {
    "ios": {
      "app_id": "YOUR_FACEBOOK_APP_ID_IOS",
      "client_token": "YOUR_FACEBOOK_CLIENT_TOKEN_IOS"
    },
    "android": {
      "app_id": "YOUR_FACEBOOK_APP_ID_ANDROID",
      "client_token": "YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID"
    },
    "auto_log_app_events_enabled": true,
    "advertiser_tracking_enabled": true
  },
  "singular": {
    "ios": {
      "api_key": "YOUR_SINGULAR_API_KEY_IOS",
      "secret": "YOUR_SINGULAR_SECRET_IOS"
    },
    "android": {
      "api_key": "YOUR_SINGULAR_API_KEY_ANDROID",
      "secret": "YOUR_SINGULAR_SECRET_ANDROID"
    },
    "enable_logging": true,
    "wait_for_tracking_auth_seconds": 15
  }
}
''';

const String _invalidSingularRemoteJson = '''
{
  "version": 1,
  "enable_facebook": false,
  "enable_singular": true,
  "facebook": {
    "ios": {
      "app_id": "",
      "client_token": ""
    },
    "android": {
      "app_id": "",
      "client_token": ""
    }
  },
  "singular": {
    "ios": {
      "api_key": "",
      "secret": ""
    },
    "android": {
      "api_key": "",
      "secret": ""
    }
  }
}
''';

const String _invalidFacebookRemoteJson = '''
{
  "version": 1,
  "enable_facebook": true,
  "enable_singular": false,
  "facebook": {
    "ios": {
      "app_id": "fb_app_ios",
      "client_token": ""
    },
    "android": {
      "app_id": "fb_app_android",
      "client_token": ""
    }
  },
  "singular": {
    "ios": {
      "api_key": "",
      "secret": ""
    },
    "android": {
      "api_key": "",
      "secret": ""
    }
  }
}
''';

class _FakeConfigHttpClient implements AnalyticsConfigHttpClient {
  _FakeConfigHttpClient(this.response);

  final String response;

  @override
  Future<String> get(Uri url, Duration timeout) async => response;
}

class _FailingConfigHttpClient implements AnalyticsConfigHttpClient {
  @override
  Future<String> get(Uri url, Duration timeout) async {
    throw Exception('network down');
  }
}

class _SequenceConfigHttpClient implements AnalyticsConfigHttpClient {
  _SequenceConfigHttpClient(this.responses);

  final List<Object> responses;
  int callCount = 0;

  @override
  Future<String> get(Uri url, Duration timeout) async {
    final index = callCount;
    callCount += 1;
    final response = responses[index];
    if (response is String) {
      return response;
    }
    throw response;
  }
}

class _CompleterConfigHttpClient implements AnalyticsConfigHttpClient {
  _CompleterConfigHttpClient(this.response);

  final Future<String> response;
  int callCount = 0;

  @override
  Future<String> get(Uri url, Duration timeout) {
    callCount += 1;
    return response;
  }
}

class _MemoryConfigCache implements AnalyticsConfigCache {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _BlockingFirstSaveEventStore implements AnalyticsEventStore {
  final Completer<void> firstSaveStarted = Completer<void>();
  final Completer<void> releaseFirstSave = Completer<void>();
  List<AnalyticsEvent> events = <AnalyticsEvent>[];
  var _saveCount = 0;

  @override
  Future<List<AnalyticsEvent>> load() async => List<AnalyticsEvent>.of(events);

  @override
  Future<void> save(List<AnalyticsEvent> events) async {
    _saveCount += 1;
    if (_saveCount == 1) {
      firstSaveStarted.complete();
      await releaseFirstSave.future;
    }
    this.events = List<AnalyticsEvent>.of(events);
  }
}

class _RecordingEventStore implements AnalyticsEventStore {
  _RecordingEventStore({List<AnalyticsEvent>? events})
    : events = List<AnalyticsEvent>.of(events ?? const <AnalyticsEvent>[]);

  List<AnalyticsEvent> events;
  int saveCount = 0;

  @override
  Future<List<AnalyticsEvent>> load() async => List<AnalyticsEvent>.of(events);

  @override
  Future<void> save(List<AnalyticsEvent> events) async {
    saveCount += 1;
    this.events = List<AnalyticsEvent>.of(events);
  }
}

class _RecordingTrackingAuthorizationRequester
    implements TrackingAuthorizationRequester {
  _RecordingTrackingAuthorizationRequester(this.order);

  final List<String> order;
  int requestCount = 0;

  @override
  Future<void> requestIfNeeded() async {
    requestCount += 1;
    order.add('att');
  }
}

class _FailingAnalyticsProvider extends InMemoryAnalyticsProvider {
  @override
  String get name => 'failing';

  @override
  Future<void> track(AnalyticsEvent event) async {
    throw StateError('delivery failed');
  }
}

class _FailOnceAnalyticsProvider extends InMemoryAnalyticsProvider {
  var _shouldFail = true;
  final List<String> successfulEvents = <String>[];

  @override
  String get name => 'fail_once';

  @override
  Future<void> track(AnalyticsEvent event) async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('delivery failed once');
    }
    successfulEvents.add(event.name);
  }
}

class _OrderingAnalyticsProvider extends InMemoryAnalyticsProvider {
  _OrderingAnalyticsProvider(this.order);

  final List<String> order;

  @override
  Future<void> initialize() async {
    order.add('provider');
  }
}

class _RecordingFacebookAppEvents extends FacebookAppEvents {
  String? configuredAppId;
  String? configuredClientToken;
  bool? configuredAutoLogAppEventsEnabled;
  bool? configuredAdvertiserIdCollectionEnabled;
  bool? debugLoggingEnabled;
  int flushCount = 0;
  String? lastName;
  Map<String, dynamic>? lastParameters;
  double? lastValueToSum;
  double? lastPurchaseAmount;
  String? lastPurchaseCurrency;

  @override
  Future<void> configure({
    required String appId,
    required String clientToken,
    bool? autoLogAppEventsEnabled,
    bool? advertiserIdCollectionEnabled,
  }) async {
    configuredAppId = appId;
    configuredClientToken = clientToken;
    configuredAutoLogAppEventsEnabled = autoLogAppEventsEnabled;
    configuredAdvertiserIdCollectionEnabled = advertiserIdCollectionEnabled;
  }

  @override
  Future<void> setDebugLoggingEnabled(bool enabled) async {
    debugLoggingEnabled = enabled;
  }

  @override
  Future<void> flush() async {
    flushCount += 1;
  }

  @override
  Future<void> logEvent({
    required String name,
    Map<String, dynamic>? parameters,
    double? valueToSum,
  }) async {
    lastName = name;
    lastParameters = parameters;
    lastValueToSum = valueToSum;
  }

  @override
  Future<void> logPurchase({
    required double amount,
    required String currency,
    Map<String, dynamic>? parameters,
  }) async {
    lastPurchaseAmount = amount;
    lastPurchaseCurrency = currency;
    lastParameters = parameters;
  }
}

class _RecordingSingularSdkFacade implements SingularSdkFacade {
  final List<String> calls = <String>[];
  String? lastEventName;
  String? lastCurrency;
  double? lastAmount;
  Map? lastArgs;

  @override
  Future<void> start(SingularConfig config) async {
    calls.add('start');
  }

  @override
  Future<void> event(String eventName) async {
    calls.add('event');
    lastEventName = eventName;
  }

  @override
  Future<void> eventWithArgs(String eventName, Map args) async {
    calls.add('eventWithArgs');
    lastEventName = eventName;
    lastArgs = args;
  }

  @override
  Future<void> customRevenue(
    String eventName,
    String currency,
    double amount,
  ) async {
    calls.add('customRevenue');
    lastEventName = eventName;
    lastCurrency = currency;
    lastAmount = amount;
  }

  @override
  Future<void> customRevenueWithAttributes(
    String eventName,
    String currency,
    double amount,
    Map attributes,
  ) async {
    calls.add('customRevenueWithAttributes');
    lastEventName = eventName;
    lastCurrency = currency;
    lastAmount = amount;
    lastArgs = attributes;
  }

  @override
  Future<void> setCustomUserId(String customUserId) async {}

  @override
  Future<void> unsetCustomUserId() async {}
}

class _FailingSingularSdkFacade extends _RecordingSingularSdkFacade {
  @override
  Future<void> event(String eventName) async {
    throw StateError('Singular platform delivery failed');
  }
}
