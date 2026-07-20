import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_event_store.dart';
import 'analytics_exception.dart';
import 'analytics_provider.dart';
import 'providers/facebook_provider.dart';
import 'providers/singular_provider.dart';
import 'remote_analytics_config.dart';
import 'tracking_authorization.dart';

class CompanyAnalytics {
  static const int defaultMaxPendingEvents = 200;

  CompanyAnalytics({
    List<AnalyticsProvider>? providers,
    this.failFastBeforeInit = false,
    TrackingAuthorizationRequester? trackingAuthorizationRequester,
    AnalyticsEventStore? eventStore,
    this.maxPendingEvents = defaultMaxPendingEvents,
  }) : _customProviders = providers,
       assert(maxPendingEvents > 0),
       _eventStore = eventStore ?? SharedPreferencesAnalyticsEventStore(),
       _trackingAuthorizationRequester =
           trackingAuthorizationRequester ?? AppTrackingTransparencyRequester();

  final List<AnalyticsProvider>? _customProviders;
  final bool failFastBeforeInit;
  final TrackingAuthorizationRequester _trackingAuthorizationRequester;
  final AnalyticsEventStore _eventStore;
  final int maxPendingEvents;
  final Queue<AnalyticsEvent> _pendingEvents = Queue<AnalyticsEvent>();

  bool _isInitialized = false;

  AnalyticsConfig? _config;
  RemoteAnalyticsConfigResult? _lastRemoteConfigResult;
  RemoteAnalyticsConfig? _lastRemoteConfig;
  RemoteAnalyticsConfigLoader? _lastRemoteConfigLoader;
  bool _lastFacebookTestModeEnabled = false;
  Future<void>? _remoteInitAttempt;
  Future<void>? _configInitAttempt;
  Future<void>? _pendingEventsLoadAttempt;
  Future<void>? _pendingEventsDrainAttempt;
  Future<void> _pendingEventsSaveTail = Future<void>.value();
  bool _pendingEventsLoaded = false;
  int _droppedPendingEventCount = 0;
  List<AnalyticsProvider> _providers = const <AnalyticsProvider>[];

  bool get isInitialized => _isInitialized;

  int get droppedPendingEventCount => _droppedPendingEventCount;

  RemoteAnalyticsConfigResult? get lastRemoteConfigResult {
    return _lastRemoteConfigResult;
  }

  Future<void> _initFromConfig(
    AnalyticsConfig config, {
    bool facebookTestModeEnabled = false,
  }) {
    if (_isInitialized) {
      return Future<void>.value();
    }

    final runningAttempt = _configInitAttempt;
    if (runningAttempt != null) {
      return runningAttempt;
    }

    final attempt = _performInitFromConfig(
      config,
      facebookTestModeEnabled: facebookTestModeEnabled,
    );
    _configInitAttempt = attempt;
    return attempt.whenComplete(() {
      if (identical(_configInitAttempt, attempt)) {
        _configInitAttempt = null;
      }
    });
  }

  Future<void> _performInitFromConfig(
    AnalyticsConfig config, {
    bool facebookTestModeEnabled = false,
  }) async {
    await _ensurePendingEventsLoaded();
    final errors = config.validate(
      hasCustomProviders: _customProviders?.isNotEmpty ?? false,
    );
    if (errors.isNotEmpty) {
      throw AnalyticsInitializationException(errors.join(' | '));
    }

    _config = config;

    try {
      await _trackingAuthorizationRequester.requestIfNeeded();
      _providers =
          _customProviders ??
          _buildDefaultProviders(
            config,
            facebookTestModeEnabled: facebookTestModeEnabled,
          );

      for (final provider in _providers) {
        await provider.initialize();
      }

      _isInitialized = true;

      if (config.queueEventsBeforeInit) {
        try {
          await _drainPendingEvents();
        } catch (error) {
          debugPrint(
            '[company_analytics] Pending event delivery failed and will be retried: $error',
          );
        }
      } else {
        _pendingEvents.clear();
        await _persistPendingEvents();
      }
    } catch (error) {
      throw AnalyticsInitializationException(
        'Analytics initialization failed.',
        error,
      );
    }
  }

  Future<void> initFromRemoteConfig(
    RemoteAnalyticsConfig remoteConfig, {
    RemoteAnalyticsConfigLoader? loader,
    bool facebookTestModeEnabled = false,
  }) async {
    if (_isInitialized) {
      return;
    }

    final runningAttempt = _remoteInitAttempt;
    if (runningAttempt != null) {
      await runningAttempt;
      return;
    }

    final configLoader = loader ?? RemoteAnalyticsConfigLoader();
    _lastRemoteConfig = remoteConfig;
    _lastRemoteConfigLoader = configLoader;
    _lastFacebookTestModeEnabled = facebookTestModeEnabled;
    final attempt = _loadAndInitFromRemoteConfig(
      remoteConfig,
      configLoader,
      facebookTestModeEnabled: facebookTestModeEnabled,
    );
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
    RemoteAnalyticsConfigLoader configLoader, {
    bool facebookTestModeEnabled = false,
  }) async {
    final result = await configLoader.loadResult(remoteConfig);
    _lastRemoteConfigResult = result;
    await _initFromConfig(
      result.config,
      facebookTestModeEnabled: facebookTestModeEnabled,
    );
  }

  Future<void> track(AnalyticsEvent event) async {
    event.validate();
    await _ensurePendingEventsLoaded();
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
        if (_pendingEvents.length >= maxPendingEvents) {
          _pendingEvents.removeFirst();
          _droppedPendingEventCount += 1;
          debugPrint(
            '[company_analytics] Pending event outbox reached '
            '$maxPendingEvents events; dropped the oldest event.',
          );
        }
        _pendingEvents.add(event);
        await _persistPendingEvents();
        return;
      }

      return;
    }

    if (_pendingEvents.isNotEmpty) {
      try {
        await _drainPendingEvents();
      } catch (error) {
        debugPrint(
          '[company_analytics] Pending event delivery failed and will be retried: $error',
        );
      }
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
        facebookTestModeEnabled: _lastFacebookTestModeEnabled,
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
    final providerErrors = <String, Object>{};
    for (final provider in _providers) {
      final sendToFacebook =
          provider is FacebookAnalyticsProvider && event.sendToFacebook;
      final sendToSingular =
          provider is SingularAnalyticsProvider && event.sendToSingular;
      final sendToAllOthers =
          provider is! FacebookAnalyticsProvider &&
          provider is! SingularAnalyticsProvider;

      if (sendToFacebook || sendToSingular || sendToAllOthers) {
        try {
          await provider.track(event);
        } catch (error) {
          providerErrors[provider.name] = error;
        }
      }
    }

    if (providerErrors.isNotEmpty) {
      throw AnalyticsDeliveryException(event.name, providerErrors);
    }
  }

  Future<void> _drainPendingEvents() {
    final runningAttempt = _pendingEventsDrainAttempt;
    if (runningAttempt != null) {
      return runningAttempt;
    }
    final attempt = _performDrainPendingEvents();
    _pendingEventsDrainAttempt = attempt;
    return attempt.whenComplete(() {
      if (identical(_pendingEventsDrainAttempt, attempt)) {
        _pendingEventsDrainAttempt = null;
      }
    });
  }

  Future<void> _performDrainPendingEvents() async {
    var changed = false;
    try {
      while (_pendingEvents.isNotEmpty) {
        final event = _pendingEvents.first;
        await _trackToProviders(event);
        _pendingEvents.removeFirst();
        changed = true;
      }
    } finally {
      if (changed) {
        // Persist the remaining outbox once per drain attempt. If the process
        // exits before this write, already delivered events may be replayed,
        // which is consistent with the documented at-least-once semantics.
        await _persistPendingEvents();
      }
    }
  }

  Future<void> _ensurePendingEventsLoaded() {
    if (_pendingEventsLoaded) {
      return Future<void>.value();
    }
    final runningAttempt = _pendingEventsLoadAttempt;
    if (runningAttempt != null) {
      return runningAttempt;
    }
    final attempt = _loadPendingEvents();
    _pendingEventsLoadAttempt = attempt;
    return attempt.whenComplete(() {
      if (identical(_pendingEventsLoadAttempt, attempt)) {
        _pendingEventsLoadAttempt = null;
      }
    });
  }

  Future<void> _loadPendingEvents() async {
    final storedEvents = await _eventStore.load();
    final overflow = storedEvents.length - maxPendingEvents;
    if (overflow > 0) {
      _droppedPendingEventCount += overflow;
      _pendingEvents.addAll(storedEvents.skip(overflow));
      debugPrint(
        '[company_analytics] Stored pending event outbox exceeded '
        '$maxPendingEvents events; dropped $overflow oldest events.',
      );
    } else {
      _pendingEvents.addAll(storedEvents);
    }
    _pendingEventsLoaded = true;
    if (overflow > 0) {
      await _persistPendingEvents();
    }
  }

  Future<void> _persistPendingEvents() {
    final snapshot = _pendingEvents.toList(growable: false);
    final attempt = _pendingEventsSaveTail.then(
      (_) => _eventStore.save(snapshot),
    );
    _pendingEventsSaveTail = attempt.then<void>((_) {}, onError: (_, _) {});
    return attempt;
  }

  void _assertInitialized(String action) {
    if (!_isInitialized) {
      throw AnalyticsNotInitializedException('$action called before init().');
    }
  }

  static List<AnalyticsProvider> _buildDefaultProviders(
    AnalyticsConfig config, {
    bool facebookTestModeEnabled = false,
  }) {
    final providers = <AnalyticsProvider>[];

    if (config.enableFacebook) {
      providers.add(
        FacebookAnalyticsProvider(
          appId: config.facebookAppId,
          clientToken: config.facebookClientToken,
          autoLogAppEventsEnabled: config.facebookAutoLogAppEventsEnabled,
          advertiserTrackingEnabled: config.facebookAdvertiserTrackingEnabled,
          testModeEnabled: facebookTestModeEnabled,
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
