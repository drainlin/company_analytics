import 'dart:collection';

import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:singular_flutter_sdk/attributes.dart';
import 'package:singular_flutter_sdk/events.dart';

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
  bool _lastFacebookDebugLoggingEnabled = !kReleaseMode;
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
    required bool facebookDebugLoggingEnabled,
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
      facebookDebugLoggingEnabled: facebookDebugLoggingEnabled,
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
    required bool facebookDebugLoggingEnabled,
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
            facebookDebugLoggingEnabled: facebookDebugLoggingEnabled,
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
    bool? facebookDebugLoggingEnabled,
    @Deprecated(
      'Use facebookDebugLoggingEnabled. This alias will be removed in a future release.',
    )
    bool? facebookTestModeEnabled,
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
    final resolvedFacebookDebugLoggingEnabled =
        _resolveFacebookDebugLoggingEnabled(
          facebookDebugLoggingEnabled: facebookDebugLoggingEnabled,
          facebookTestModeEnabled: facebookTestModeEnabled,
        );
    _lastRemoteConfig = remoteConfig;
    _lastRemoteConfigLoader = configLoader;
    _lastFacebookDebugLoggingEnabled = resolvedFacebookDebugLoggingEnabled;
    final attempt = _loadAndInitFromRemoteConfig(
      remoteConfig,
      configLoader,
      facebookDebugLoggingEnabled: resolvedFacebookDebugLoggingEnabled,
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
    required bool facebookDebugLoggingEnabled,
  }) async {
    final result = await configLoader.loadResult(remoteConfig);
    _lastRemoteConfigResult = result;
    await _initFromConfig(
      result.config,
      facebookDebugLoggingEnabled: facebookDebugLoggingEnabled,
    );
  }

  /// Reports a new paid subscription to Singular only.
  ///
  /// Subscription receipts are intentionally excluded. Restored subscriptions
  /// must not call this method because they do not represent new revenue.
  Future<void> trackSingularSubscription({
    required double amount,
    required String currency,
    required String subscriptionId,
    String? transactionId,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    _validateRevenue(amount, currency);
    final normalizedSubscriptionId = subscriptionId.trim();
    if (normalizedSubscriptionId.isEmpty) {
      throw const AnalyticsEventValidationException(
        'subscriptionId must not be empty.',
      );
    }
    final normalizedTransactionId = transactionId?.trim();
    if (normalizedTransactionId?.isEmpty ?? false) {
      throw const AnalyticsEventValidationException(
        'transactionId must not be empty when provided.',
      );
    }

    return _track(
      AnalyticsEvent(
        name: Events.sngSubscribe,
        parameters: <String, dynamic>{
          ...attributes,
          Attributes.sngAttrSubscriptionId: normalizedSubscriptionId,
          Attributes.sngAttrTransactionId: ?normalizedTransactionId,
        },
        valueToSum: amount,
        revenueCurrency: currency,
        sendToFacebook: false,
        sendToCustomProviders: false,
      ),
    );
  }

  /// Reports the start of a free trial to Singular only.
  ///
  /// Trial starts are standard non-revenue events.
  Future<void> trackSingularTrialStart({
    required String transactionId,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    final normalizedTransactionId = transactionId.trim();
    if (normalizedTransactionId.isEmpty) {
      throw const AnalyticsEventValidationException(
        'transactionId must not be empty.',
      );
    }

    return _track(
      AnalyticsEvent(
        name: Events.sngStartTrial,
        parameters: <String, dynamic>{
          ...attributes,
          Attributes.sngAttrTransactionId: normalizedTransactionId,
        },
        sendToFacebook: false,
        sendToCustomProviders: false,
      ),
    );
  }

  /// Reports a verified free-trial start to Meta only.
  ///
  /// Use this after the store transaction has passed the host application's
  /// server-side verification. It compensates for Meta automatic purchase
  /// logging classifying a free trial as a paid subscription. Restored
  /// subscriptions must not call this method.
  Future<void> trackFacebookTrialStart({
    required double subscriptionValue,
    required String currency,
    required String subscriptionId,
    required String transactionId,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) {
    _validateRevenue(subscriptionValue, currency);
    final normalizedSubscriptionId = subscriptionId.trim();
    if (normalizedSubscriptionId.isEmpty) {
      throw const AnalyticsEventValidationException(
        'subscriptionId must not be empty.',
      );
    }
    final normalizedTransactionId = transactionId.trim();
    if (normalizedTransactionId.isEmpty) {
      throw const AnalyticsEventValidationException(
        'transactionId must not be empty.',
      );
    }

    return _track(
      AnalyticsEvent(
        name: FacebookAppEvents.eventNameStartTrial,
        parameters: <String, dynamic>{
          ...attributes,
          FacebookAppEvents.paramNameContentId: normalizedSubscriptionId,
          FacebookAppEvents.paramNameContentType: 'subscription',
          FacebookAppEvents.paramNameOrderId: normalizedTransactionId,
        },
        valueToSum: subscriptionValue,
        revenueCurrency: currency,
        sendToFacebook: true,
        sendToSingular: false,
        sendToCustomProviders: false,
      ),
    );
  }

  /// Reports a newly completed non-subscription store purchase to Singular.
  ///
  /// The purchase must have [PurchaseStatus.purchased] and match [product].
  /// This method does not complete or acknowledge the store transaction.
  /// Unlike serializable events, purchase receipts are never persisted in the
  /// SharedPreferences outbox, so analytics must already be initialized.
  Future<void> trackSingularInAppPurchase({
    required PurchaseDetails purchase,
    required ProductDetails product,
    Map<String, dynamic> attributes = const <String, dynamic>{},
  }) async {
    _validateRevenue(product.rawPrice, product.currencyCode);
    if (purchase.status != PurchaseStatus.purchased) {
      throw const AnalyticsEventValidationException(
        'Only newly purchased in-app purchases can be reported to Singular.',
      );
    }
    if (purchase.productID != product.id) {
      throw const AnalyticsEventValidationException(
        'Purchase product id must match ProductDetails.id.',
      );
    }
    await _ensurePendingEventsLoaded();
    if (!_isInitialized) {
      await _retryRemoteInitIfPossible();
    }
    if (!_isInitialized) {
      throw AnalyticsNotInitializedException(
        'trackSingularInAppPurchase() called before init().',
      );
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

    final providerErrors = <String, Object>{};
    for (final provider in _providers.whereType<SingularAnalyticsProvider>()) {
      try {
        await provider.trackInAppPurchase(
          purchase,
          product,
          attributes: attributes,
        );
      } catch (error) {
        providerErrors[provider.name] = error;
      }
    }
    if (providerErrors.isNotEmpty) {
      throw AnalyticsDeliveryException(
        Events.sngEcommercePurchase,
        providerErrors,
      );
    }
  }

  /// Reports an exceptional custom event to explicitly selected destinations.
  ///
  /// Normal purchase, subscription, and trial flows should use the fixed
  /// Singular methods instead. [targets] must not be empty so Facebook can
  /// never receive a custom event accidentally.
  Future<void> trackCustomEvent({
    required String name,
    Map<String, dynamic> parameters = const <String, dynamic>{},
    double? valueToSum,
    String? revenueCurrency,
    required Set<AnalyticsTarget> targets,
  }) {
    if (targets.isEmpty) {
      throw const AnalyticsEventValidationException(
        'At least one custom event target is required.',
      );
    }
    return _track(
      AnalyticsEvent(
        name: name,
        parameters: parameters,
        valueToSum: valueToSum,
        revenueCurrency: revenueCurrency,
        sendToFacebook: targets.contains(AnalyticsTarget.facebook),
        sendToSingular: targets.contains(AnalyticsTarget.singular),
        sendToCustomProviders: false,
      ),
    );
  }

  /// Reports a legacy generic event.
  ///
  /// Prefer the fixed Singular methods or [trackCustomEvent], whose explicit
  /// destination selection prevents accidental Facebook duplication.
  @Deprecated(
    'Use trackSingularSubscription, trackSingularTrialStart, '
    'trackFacebookTrialStart, trackSingularInAppPurchase, or trackCustomEvent.',
  )
  Future<void> track(AnalyticsEvent event) => _track(event);

  Future<void> _track(AnalyticsEvent event) async {
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

  static void _validateRevenue(double amount, String currency) {
    if (!amount.isFinite || amount <= 0) {
      throw const AnalyticsEventValidationException(
        'Revenue amount must be finite and greater than zero.',
      );
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const AnalyticsEventValidationException(
        'Revenue currency must be a three-letter uppercase ISO 4217 code.',
      );
    }
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
        facebookDebugLoggingEnabled: _lastFacebookDebugLoggingEnabled,
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
          provider is! SingularAnalyticsProvider &&
          event.sendToCustomProviders;

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
    required bool facebookDebugLoggingEnabled,
  }) {
    final providers = <AnalyticsProvider>[];

    if (config.enableFacebook) {
      providers.add(
        FacebookAnalyticsProvider(
          appId: config.facebookAppId,
          clientToken: config.facebookClientToken,
          autoLogAppEventsEnabled: config.facebookAutoLogAppEventsEnabled,
          advertiserTrackingEnabled: config.facebookAdvertiserTrackingEnabled,
          debugLoggingEnabled: facebookDebugLoggingEnabled,
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

  static bool _resolveFacebookDebugLoggingEnabled({
    required bool? facebookDebugLoggingEnabled,
    required bool? facebookTestModeEnabled,
  }) {
    if (facebookDebugLoggingEnabled != null &&
        facebookTestModeEnabled != null) {
      throw ArgumentError(
        'Pass only facebookDebugLoggingEnabled. '
        'facebookTestModeEnabled is a deprecated alias.',
      );
    }
    return facebookDebugLoggingEnabled ??
        facebookTestModeEnabled ??
        !kReleaseMode;
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
