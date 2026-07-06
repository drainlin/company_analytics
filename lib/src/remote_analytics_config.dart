import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_config.dart';
import 'analytics_exception.dart';

class RemoteAnalyticsConfig {
  const RemoteAnalyticsConfig({
    required this.url,
    this.timeout = const Duration(seconds: 15),
    this.cacheKey = _defaultCacheKey,
    this.useCachedConfigOnFailure = true,
    this.maxAttempts = 3,
    this.retryDelay = const Duration(milliseconds: 500),
    this.retryBackoffMultiplier = 2,
  }) : assert(maxAttempts > 0),
       assert(retryBackoffMultiplier >= 1);

  static const String _defaultCacheKey = 'company_analytics.remote_config_json';

  final Uri url;
  final Duration timeout;
  final String cacheKey;
  final bool useCachedConfigOnFailure;
  final int maxAttempts;
  final Duration retryDelay;
  final double retryBackoffMultiplier;
}

abstract class AnalyticsConfigHttpClient {
  Future<String> get(Uri url, Duration timeout);
}

class HttpClientAnalyticsConfigHttpClient implements AnalyticsConfigHttpClient {
  @override
  Future<String> get(Uri url, Duration timeout) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(url)
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'Timed out opening remote analytics config URL $url.',
              timeout,
            ),
          );
      final response = await request.close().timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for remote analytics config response from $url.',
          timeout,
        ),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'Timed out reading remote analytics config body from $url.',
              timeout,
            ),
          );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Remote analytics config returned HTTP ${response.statusCode}.',
          uri: url,
        );
      }

      return body;
    } finally {
      client.close(force: true);
    }
  }
}

abstract class AnalyticsConfigCache {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SharedPreferencesAnalyticsConfigCache implements AnalyticsConfigCache {
  SharedPreferencesAnalyticsConfigCache({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> read(String key) {
    return _preferences.getString(key);
  }

  @override
  Future<void> write(String key, String value) {
    return _preferences.setString(key, value);
  }

  @override
  Future<void> delete(String key) {
    return _preferences.remove(key);
  }
}

enum RemoteAnalyticsConfigSource { remote, cache }

class RemoteAnalyticsConfigMetadata {
  const RemoteAnalyticsConfigMetadata({
    required this.sha256,
    required this.sourceUrl,
    required this.cachedAt,
    this.version,
  });

  final String sha256;
  final String sourceUrl;
  final DateTime cachedAt;
  final int? version;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sha256': sha256,
      'source_url': sourceUrl,
      'cached_at': cachedAt.toIso8601String(),
      'version': version,
    };
  }

  static RemoteAnalyticsConfigMetadata? tryParse(String? jsonString) {
    if (jsonString == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, Object?>) {
        return null;
      }

      final sha256 = decoded['sha256'];
      final sourceUrl = decoded['source_url'];
      final cachedAt = decoded['cached_at'];
      if (sha256 is! String || sourceUrl is! String || cachedAt is! String) {
        return null;
      }

      return RemoteAnalyticsConfigMetadata(
        sha256: sha256,
        sourceUrl: sourceUrl,
        cachedAt: DateTime.parse(cachedAt),
        version: decoded['version'] is int ? decoded['version'] as int : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class RemoteAnalyticsConfigResult {
  const RemoteAnalyticsConfigResult({
    required this.config,
    required this.source,
    this.changedFromCache = false,
    this.metadata,
    this.previousMetadata,
  });

  final AnalyticsConfig config;
  final RemoteAnalyticsConfigSource source;
  final bool changedFromCache;
  final RemoteAnalyticsConfigMetadata? metadata;
  final RemoteAnalyticsConfigMetadata? previousMetadata;
}

class RemoteAnalyticsConfigLoader {
  RemoteAnalyticsConfigLoader({
    AnalyticsConfigHttpClient? httpClient,
    AnalyticsConfigCache? cache,
    TargetPlatform? platform,
  }) : _httpClient = httpClient ?? HttpClientAnalyticsConfigHttpClient(),
       _cache = cache ?? SharedPreferencesAnalyticsConfigCache(),
       _platform = platform;

  final AnalyticsConfigHttpClient _httpClient;
  final AnalyticsConfigCache _cache;
  final TargetPlatform? _platform;

  Future<AnalyticsConfig> load(RemoteAnalyticsConfig remoteConfig) async {
    final result = await loadResult(remoteConfig);
    return result.config;
  }

  Future<RemoteAnalyticsConfigResult> loadResult(
    RemoteAnalyticsConfig remoteConfig,
  ) async {
    Object? remoteError;

    for (var attempt = 1; attempt <= remoteConfig.maxAttempts; attempt += 1) {
      try {
        return await _loadRemoteResult(remoteConfig);
      } catch (error) {
        remoteError = error;
        _printRemoteConfigFailure(
          remoteConfig: remoteConfig,
          attempt: attempt,
          error: error,
        );
        if (attempt < remoteConfig.maxAttempts) {
          await Future<void>.delayed(_retryDelay(remoteConfig, attempt));
        }
      }
    }

    if (!remoteConfig.useCachedConfigOnFailure) {
      throw AnalyticsInitializationException(
        'Failed to load remote analytics config.',
        remoteError,
      );
    }

    final cachedJson = await _cache.read(remoteConfig.cacheKey);
    if (cachedJson == null) {
      _printRemoteConfigCacheMiss(remoteConfig);
      throw AnalyticsInitializationException(
        'Failed to load remote analytics config and no cached config exists.',
        remoteError,
      );
    }

    try {
      _printRemoteConfigUsingCache(remoteConfig);
      return RemoteAnalyticsConfigResult(
        config: parse(cachedJson),
        source: RemoteAnalyticsConfigSource.cache,
        metadata: await _readMetadata(remoteConfig.cacheKey),
      );
    } catch (cacheError) {
      throw AnalyticsInitializationException(
        'Failed to parse cached analytics config.',
        cacheError,
      );
    }
  }

  static void _printRemoteConfigFailure({
    required RemoteAnalyticsConfig remoteConfig,
    required int attempt,
    required Object error,
  }) {
    // ignore: avoid_print
    print(
      '[company_analytics] Remote config request failed. '
      'attempt=$attempt/${remoteConfig.maxAttempts} '
      'url=${remoteConfig.url} '
      'timeout=${remoteConfig.timeout.inSeconds}s '
      'error=$error',
    );
  }

  static void _printRemoteConfigCacheMiss(RemoteAnalyticsConfig remoteConfig) {
    // ignore: avoid_print
    print(
      '[company_analytics] Remote config cache miss. '
      'cacheKey=${remoteConfig.cacheKey}',
    );
  }

  static void _printRemoteConfigUsingCache(RemoteAnalyticsConfig remoteConfig) {
    // ignore: avoid_print
    print(
      '[company_analytics] Using cached remote config. '
      'cacheKey=${remoteConfig.cacheKey}',
    );
  }

  Future<RemoteAnalyticsConfigResult> _loadRemoteResult(
    RemoteAnalyticsConfig remoteConfig,
  ) async {
    final jsonString = await _httpClient.get(
      remoteConfig.url,
      remoteConfig.timeout,
    );
    final config = parse(jsonString);
    final metadata = _buildMetadata(jsonString, remoteConfig.url);
    final previousMetadata = await _readMetadata(remoteConfig.cacheKey);
    await _cache.write(remoteConfig.cacheKey, jsonString);
    await _cache.write(
      _metadataCacheKey(remoteConfig.cacheKey),
      jsonEncode(metadata.toJson()),
    );
    return RemoteAnalyticsConfigResult(
      config: config,
      source: RemoteAnalyticsConfigSource.remote,
      changedFromCache:
          previousMetadata != null &&
          previousMetadata.sha256 != metadata.sha256,
      metadata: metadata,
      previousMetadata: previousMetadata,
    );
  }

  static Duration _retryDelay(RemoteAnalyticsConfig remoteConfig, int attempt) {
    final multiplier = _pow(remoteConfig.retryBackoffMultiplier, attempt - 1);
    return Duration(
      microseconds: (remoteConfig.retryDelay.inMicroseconds * multiplier)
          .round(),
    );
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i += 1) {
      result *= base;
    }
    return result;
  }

  Future<void> clearCache(RemoteAnalyticsConfig remoteConfig) async {
    await _cache.delete(remoteConfig.cacheKey);
    await _cache.delete(_metadataCacheKey(remoteConfig.cacheKey));
  }

  Future<RemoteAnalyticsConfigMetadata?> _readMetadata(String cacheKey) async {
    return RemoteAnalyticsConfigMetadata.tryParse(
      await _cache.read(_metadataCacheKey(cacheKey)),
    );
  }

  @visibleForTesting
  AnalyticsConfig parse(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException(
        'Remote analytics config must be a JSON map.',
      );
    }

    final platformKey = _platformKey(_platform ?? defaultTargetPlatform);
    final facebookEnabledByConfig = _readBool(
      decoded,
      'enable_facebook',
      fallback: true,
    );
    final singularEnabledByConfig = _readBool(
      decoded,
      'enable_singular',
      fallback: true,
    );

    final facebook = _readOptionalMap(decoded, 'facebook');
    final singular = _readOptionalMap(decoded, 'singular');

    String? facebookAppId;
    String? facebookClientToken;
    if (facebookEnabledByConfig) {
      final facebookPlatform = _readPlatformMap(
        _requireMap(facebook, 'facebook'),
        platformKey,
      );
      facebookAppId = _readRequiredString(facebookPlatform, 'app_id');
      facebookClientToken = _readRequiredString(
        facebookPlatform,
        'client_token',
      );
    }

    var singularApiKey = '';
    var singularSecret = '';
    if (singularEnabledByConfig) {
      final singularPlatform = _readPlatformMap(
        _requireMap(singular, 'singular'),
        platformKey,
      );
      singularApiKey = _readRequiredString(singularPlatform, 'api_key');
      singularSecret = _readRequiredString(singularPlatform, 'secret');
    }

    final enableFacebook =
        facebookEnabledByConfig &&
        !_hasDefaultPlaceholder(<String?>[facebookAppId, facebookClientToken]);
    final enableSingular =
        singularEnabledByConfig &&
        !_hasDefaultPlaceholder(<String?>[singularApiKey, singularSecret]);

    return AnalyticsConfig(
      facebookAppId: facebookAppId,
      facebookClientToken: facebookClientToken,
      singularApiKey: singularApiKey,
      singularSecret: singularSecret,
      enableFacebook: enableFacebook,
      enableSingular: enableSingular,
      facebookAutoLogAppEventsEnabled: _readNullableBool(
        facebook ?? const <String, Object?>{},
        'auto_log_app_events_enabled',
      ),
      facebookAdvertiserTrackingEnabled: _readNullableBool(
        facebook ?? const <String, Object?>{},
        'advertiser_tracking_enabled',
      ),
      singularEnableLogging: _readBool(
        singular ?? const <String, Object?>{},
        'enable_logging',
        fallback: false,
      ),
      singularWaitForTrackingAuthSeconds: _readInt(
        singular ?? const <String, Object?>{},
        'wait_for_tracking_auth_seconds',
        fallback: 0,
      ),
    );
  }

  static RemoteAnalyticsConfigMetadata _buildMetadata(
    String jsonString,
    Uri url,
  ) {
    final decoded = jsonDecode(jsonString);
    final version = decoded is Map<String, Object?> && decoded['version'] is int
        ? decoded['version'] as int
        : null;
    return RemoteAnalyticsConfigMetadata(
      sha256: sha256.convert(utf8.encode(jsonString)).toString(),
      sourceUrl: url.toString(),
      cachedAt: DateTime.now().toUtc(),
      version: version,
    );
  }

  static String _metadataCacheKey(String cacheKey) {
    return '$cacheKey.metadata';
  }

  static String _platformKey(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => throw UnsupportedError(
        'Remote analytics config only supports Android and iOS.',
      ),
    };
  }

  static Map<String, Object?> _readPlatformMap(
    Map<String, Object?> source,
    String platformKey,
  ) {
    final platformValue = source[platformKey];
    if (platformValue is Map<String, Object?>) {
      return platformValue;
    }

    throw FormatException('Missing or invalid "$platformKey" section.');
  }

  static Map<String, Object?>? _readOptionalMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value == null) {
      return null;
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    throw FormatException('Missing or invalid "$key" section.');
  }

  static Map<String, Object?> _requireMap(
    Map<String, Object?>? value,
    String key,
  ) {
    if (value != null) {
      return value;
    }
    throw FormatException('Missing or invalid "$key" section.');
  }

  static String _readRequiredString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    throw FormatException('Missing or empty "$key" value.');
  }

  static bool _hasDefaultPlaceholder(Iterable<String?> values) {
    return values.any(
      (value) =>
          value != null && _defaultPlaceholderValues.contains(value.trim()),
    );
  }

  static const Set<String> _defaultPlaceholderValues = <String>{
    'YOUR_FACEBOOK_APP_ID_IOS',
    'YOUR_FACEBOOK_CLIENT_TOKEN_IOS',
    'YOUR_FACEBOOK_APP_ID_ANDROID',
    'YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID',
    'YOUR_SINGULAR_API_KEY_IOS',
    'YOUR_SINGULAR_SECRET_IOS',
    'YOUR_SINGULAR_API_KEY_ANDROID',
    'YOUR_SINGULAR_SECRET_ANDROID',
  };

  static bool _readBool(
    Map<String, Object?> source,
    String key, {
    required bool fallback,
  }) {
    final value = source[key];
    if (value == null) {
      return fallback;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('"$key" must be a boolean.');
  }

  static bool? _readNullableBool(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('"$key" must be a boolean.');
  }

  static int _readInt(
    Map<String, Object?> source,
    String key, {
    required int fallback,
  }) {
    final value = source[key];
    if (value == null) {
      return fallback;
    }
    if (value is int) {
      return value;
    }
    throw FormatException('"$key" must be an integer.');
  }
}
