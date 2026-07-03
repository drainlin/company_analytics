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
    this.timeout = const Duration(seconds: 3),
    this.cacheKey = _defaultCacheKey,
    this.useCachedConfigOnFailure = true,
  });

  static const String _defaultCacheKey = 'company_analytics.remote_config_json';

  final Uri url;
  final Duration timeout;
  final String cacheKey;
  final bool useCachedConfigOnFailure;
}

abstract class AnalyticsConfigHttpClient {
  Future<String> get(Uri url, Duration timeout);
}

class HttpClientAnalyticsConfigHttpClient implements AnalyticsConfigHttpClient {
  @override
  Future<String> get(Uri url, Duration timeout) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);

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
    try {
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
    } catch (error) {
      if (!remoteConfig.useCachedConfigOnFailure) {
        throw AnalyticsInitializationException(
          'Failed to load remote analytics config.',
          error,
        );
      }

      final cachedJson = await _cache.read(remoteConfig.cacheKey);
      if (cachedJson == null) {
        throw AnalyticsInitializationException(
          'Failed to load remote analytics config and no cached config exists.',
          error,
        );
      }

      try {
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

    final facebook = _readMap(decoded, 'facebook');
    final singular = _readMap(decoded, 'singular');
    final platformKey = _platformKey(_platform ?? defaultTargetPlatform);
    final facebookPlatform = _readPlatformMap(facebook, platformKey);
    final singularPlatform = _readPlatformMap(singular, platformKey);

    return AnalyticsConfig(
      facebookAppId: _readRequiredString(facebookPlatform, 'app_id'),
      facebookClientToken: _readRequiredString(
        facebookPlatform,
        'client_token',
      ),
      singularApiKey: _readRequiredString(singularPlatform, 'api_key'),
      singularSecret: _readRequiredString(singularPlatform, 'secret'),
      enableFacebook: _readBool(decoded, 'enable_facebook', fallback: true),
      enableSingular: _readBool(decoded, 'enable_singular', fallback: true),
      facebookAutoLogAppEventsEnabled: _readNullableBool(
        facebook,
        'auto_log_app_events_enabled',
      ),
      facebookAdvertiserTrackingEnabled: _readNullableBool(
        facebook,
        'advertiser_tracking_enabled',
      ),
      singularEnableLogging: _readBool(
        singular,
        'enable_logging',
        fallback: false,
      ),
      singularWaitForTrackingAuthSeconds: _readInt(
        singular,
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

  static Map<String, Object?> _readMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map<String, Object?>) {
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
