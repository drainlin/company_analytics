import 'dart:async';
import 'dart:convert';

import 'package:company_analytics/company_analytics.dart';
import 'package:company_analytics/src/providers/facebook_provider.dart';
import 'package:company_analytics/src/tracking_authorization.dart';
import 'package:flutter/foundation.dart';
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

    test('validates facebook runtime config before native initialization', () {
      final analytics = CompanyAnalytics();

      expect(
        () => analytics.init(
          const AnalyticsConfig(
            singularApiKey: 'fake_key',
            singularSecret: 'fake_secret',
            enableFacebook: true,
            enableSingular: false,
          ),
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
  });

  group('RemoteAnalyticsConfigLoader', () {
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

class _OrderingAnalyticsProvider extends InMemoryAnalyticsProvider {
  _OrderingAnalyticsProvider(this.order);

  final List<String> order;

  @override
  Future<void> initialize() async {
    order.add('provider');
  }
}
