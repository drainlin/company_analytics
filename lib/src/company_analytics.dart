import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_exception.dart';
import 'analytics_provider.dart';
import 'providers/facebook_provider.dart';
import 'providers/singular_provider.dart';
import 'remote_analytics_config.dart';
import 'tracking_authorization.dart';

class CompanyAnalytics {
  CompanyAnalytics({
    List<AnalyticsProvider>? providers,
    this.failFastBeforeInit = false,
    TrackingAuthorizationRequester? trackingAuthorizationRequester,
  }) : _customProviders = providers,
       _trackingAuthorizationRequester =
           trackingAuthorizationRequester ?? AppTrackingTransparencyRequester();

  final List<AnalyticsProvider>? _customProviders;
  final bool failFastBeforeInit;
  final TrackingAuthorizationRequester _trackingAuthorizationRequester;
  final Queue<AnalyticsEvent> _pendingEvents = Queue<AnalyticsEvent>();

  bool _isInitialized = false;
  bool _isInitializing = false;

  AnalyticsConfig? _config;
  RemoteAnalyticsConfigResult? _lastRemoteConfigResult;
  RemoteAnalyticsConfig? _lastRemoteConfig;
  RemoteAnalyticsConfigLoader? _lastRemoteConfigLoader;
  Future<void>? _remoteInitAttempt;
  List<AnalyticsProvider> _providers = const <AnalyticsProvider>[];

  bool get isInitialized => _isInitialized;

  RemoteAnalyticsConfigResult? get lastRemoteConfigResult {
    return _lastRemoteConfigResult;
  }

  Future<void> _initFromConfig(AnalyticsConfig config) async {
    if (_isInitialized || _isInitializing) {
      return;
    }

    final errors = config.validate(
      hasCustomProviders: _customProviders?.isNotEmpty ?? false,
    );
    if (errors.isNotEmpty) {
      throw AnalyticsInitializationException(errors.join(' | '));
    }

    _isInitializing = true;
    _config = config;

    try {
      await _trackingAuthorizationRequester.requestIfNeeded();
      _providers = _customProviders ?? _buildDefaultProviders(config);

      for (final provider in _providers) {
        await provider.initialize();
      }

      _isInitialized = true;
      _isInitializing = false;

      if (config.queueEventsBeforeInit) {
        await _drainPendingEvents();
      } else {
        _pendingEvents.clear();
      }
    } catch (error) {
      _isInitializing = false;
      throw AnalyticsInitializationException(
        'Analytics initialization failed.',
        error,
      );
    }
  }

  Future<void> initFromRemoteConfig(
    RemoteAnalyticsConfig remoteConfig, {
    RemoteAnalyticsConfigLoader? loader,
  }) async {
    final configLoader = loader ?? RemoteAnalyticsConfigLoader();
    _lastRemoteConfig = remoteConfig;
    _lastRemoteConfigLoader = configLoader;
    final attempt = _loadAndInitFromRemoteConfig(remoteConfig, configLoader);
    _remoteInitAttempt = attempt;
    try {
      await attempt;
    } finally {
      if (identical(_remoteInitAttempt, attempt)) {
        _remoteInitAttempt = null;
      }
    }
  }

  Future<void> _loadAndInitFromRemoteConfig(
    RemoteAnalyticsConfig remoteConfig,
    RemoteAnalyticsConfigLoader configLoader,
  ) async {
    final result = await configLoader.loadResult(remoteConfig);
    _lastRemoteConfigResult = result;
    await _initFromConfig(result.config);
  }

  Future<void> track(AnalyticsEvent event) async {
    if (!_isInitialized) {
      await _retryRemoteInitIfPossible();
      if (_isInitialized) {
        await _trackToProviders(event);
        return;
      }

      final shouldFailFast =
          _config?.failFastOnTrackBeforeInit ?? failFastBeforeInit;
      if (shouldFailFast) {
        throw AnalyticsNotInitializedException(
          'track(${event.name}) called before init().',
        );
      }

      final shouldQueue = _config?.queueEventsBeforeInit ?? true;
      if (shouldQueue) {
        _pendingEvents.add(event);
        return;
      }

      return;
    }

    await _trackToProviders(event);
  }

  Future<void> _retryRemoteInitIfPossible() async {
    if (_isInitialized || _lastRemoteConfig == null) {
      return;
    }

    final runningAttempt = _remoteInitAttempt;
    if (runningAttempt != null) {
      try {
        await runningAttempt;
      } catch (_) {
        // The caller falls back to the normal not-initialized behavior.
      }
      return;
    }

    try {
      await initFromRemoteConfig(
        _lastRemoteConfig!,
        loader: _lastRemoteConfigLoader,
      );
    } catch (_) {
      // The caller falls back to queueing or fail-fast behavior.
    }
  }

  Future<void> setUserId(String userId) async {
    _assertInitialized('setUserId($userId)');
    for (final provider in _providers) {
      await provider.setUserId(userId);
    }
  }

  Future<void> clearUser() async {
    _assertInitialized('clearUser()');
    for (final provider in _providers) {
      await provider.clearUser();
    }
  }

  Future<void> _trackToProviders(AnalyticsEvent event) async {
    for (final provider in _providers) {
      final sendToFacebook =
          provider is FacebookAnalyticsProvider && event.sendToFacebook;
      final sendToSingular =
          provider is SingularAnalyticsProvider && event.sendToSingular;
      final sendToAllOthers =
          provider is! FacebookAnalyticsProvider &&
          provider is! SingularAnalyticsProvider;

      if (sendToFacebook || sendToSingular || sendToAllOthers) {
        await provider.track(event);
      }
    }
  }

  Future<void> _drainPendingEvents() async {
    while (_pendingEvents.isNotEmpty) {
      final event = _pendingEvents.removeFirst();
      await _trackToProviders(event);
    }
  }

  void _assertInitialized(String action) {
    if (!_isInitialized) {
      throw AnalyticsNotInitializedException('$action called before init().');
    }
  }

  static List<AnalyticsProvider> _buildDefaultProviders(
    AnalyticsConfig config,
  ) {
    final providers = <AnalyticsProvider>[];

    if (config.enableFacebook) {
      providers.add(
        FacebookAnalyticsProvider(
          appId: config.facebookAppId,
          clientToken: config.facebookClientToken,
          autoLogAppEventsEnabled: config.facebookAutoLogAppEventsEnabled,
          advertiserTrackingEnabled: config.facebookAdvertiserTrackingEnabled,
        ),
      );
    }

    if (config.enableSingular) {
      providers.add(
        SingularAnalyticsProvider(
          apiKey: config.singularApiKey,
          secret: config.singularSecret,
          enableLogging: config.singularEnableLogging,
          waitForTrackingAuthSeconds: config.singularWaitForTrackingAuthSeconds,
        ),
      );
    }

    return providers;
  }
}

@visibleForTesting
class InMemoryAnalyticsProvider implements AnalyticsProvider {
  final List<AnalyticsEvent> trackedEvents = <AnalyticsEvent>[];
  final List<String> userIds = <String>[];

  @override
  String get name => 'in_memory';

  @override
  Future<void> clearUser() async {
    userIds.add('__cleared__');
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setUserId(String userId) async {
    userIds.add(userId);
  }

  @override
  Future<void> track(AnalyticsEvent event) async {
    trackedEvents.add(event);
  }
}
