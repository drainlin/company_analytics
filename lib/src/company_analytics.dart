import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'analytics_config.dart';
import 'analytics_event.dart';
import 'analytics_exception.dart';
import 'analytics_provider.dart';
import 'providers/facebook_provider.dart';
import 'providers/singular_provider.dart';

class CompanyAnalytics {
  CompanyAnalytics({
    List<AnalyticsProvider>? providers,
    this.failFastBeforeInit = false,
  }) : _customProviders = providers;

  final List<AnalyticsProvider>? _customProviders;
  final bool failFastBeforeInit;
  final Queue<AnalyticsEvent> _pendingEvents = Queue<AnalyticsEvent>();

  bool _isInitialized = false;
  bool _isInitializing = false;

  AnalyticsConfig? _config;
  List<AnalyticsProvider> _providers = const <AnalyticsProvider>[];

  bool get isInitialized => _isInitialized;

  Future<void> init(AnalyticsConfig config) async {
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
    _providers = _customProviders ?? _buildDefaultProviders(config);

    try {
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

  Future<void> track(AnalyticsEvent event) async {
    if (!_isInitialized) {
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
