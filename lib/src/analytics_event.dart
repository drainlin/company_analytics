/// A built-in analytics destination for exceptional custom events.
enum AnalyticsTarget {
  /// Meta Facebook App Events.
  facebook,

  /// Singular attribution events.
  singular,
}

/// A serializable analytics event used by the persistent event outbox.
class AnalyticsEvent {
  /// Creates an analytics event.
  const AnalyticsEvent({
    required this.name,
    this.parameters = const <String, dynamic>{},
    this.valueToSum,
    this.revenueCurrency,
    this.sendToFacebook = true,
    this.sendToSingular = true,
    this.sendToCustomProviders = true,
  });

  /// Stable event name sent to the selected analytics providers.
  final String name;

  /// Event attributes supported by the destination SDKs.
  final Map<String, dynamic> parameters;

  /// Optional revenue amount.
  final double? valueToSum;

  /// Optional ISO 4217 currency code paired with [valueToSum].
  final String? revenueCurrency;

  /// Whether the event may be routed to Facebook.
  final bool sendToFacebook;

  /// Whether the event may be routed to Singular.
  final bool sendToSingular;

  /// Whether legacy custom providers receive this event.
  final bool sendToCustomProviders;

  /// Whether this event contains a complete revenue amount and currency pair.
  bool get hasRevenue => valueToSum != null && revenueCurrency != null;

  /// Validates the event before queueing or delivery.
  void validate() {
    if (name.trim().isEmpty) {
      throw const AnalyticsEventValidationException(
        'Event name must not be empty.',
      );
    }
    if ((valueToSum == null) != (revenueCurrency == null)) {
      throw const AnalyticsEventValidationException(
        'valueToSum and revenueCurrency must be provided together.',
      );
    }
    if (valueToSum != null && !valueToSum!.isFinite) {
      throw const AnalyticsEventValidationException(
        'valueToSum must be finite.',
      );
    }
    if (revenueCurrency != null && revenueCurrency!.trim().isEmpty) {
      throw const AnalyticsEventValidationException(
        'revenueCurrency must not be empty.',
      );
    }
  }

  /// Converts this event to its persistent outbox representation.
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'parameters': parameters,
      'value_to_sum': valueToSum,
      'revenue_currency': revenueCurrency,
      'send_to_facebook': sendToFacebook,
      'send_to_singular': sendToSingular,
      'send_to_custom_providers': sendToCustomProviders,
    };
  }

  /// Restores a persisted event from JSON.
  factory AnalyticsEvent.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final parameters = json['parameters'];
    if (name is! String || parameters is! Map<String, Object?>) {
      throw const FormatException('Invalid pending analytics event.');
    }
    return AnalyticsEvent(
      name: name,
      parameters: Map<String, dynamic>.from(parameters),
      valueToSum: (json['value_to_sum'] as num?)?.toDouble(),
      revenueCurrency: json['revenue_currency'] as String?,
      sendToFacebook: json['send_to_facebook'] as bool? ?? true,
      sendToSingular: json['send_to_singular'] as bool? ?? true,
      sendToCustomProviders: json['send_to_custom_providers'] as bool? ?? true,
    );
  }

  /// Returns a copy with selected values replaced.
  AnalyticsEvent copyWith({
    String? name,
    Map<String, dynamic>? parameters,
    double? valueToSum,
    String? revenueCurrency,
    bool? sendToFacebook,
    bool? sendToSingular,
    bool? sendToCustomProviders,
  }) {
    return AnalyticsEvent(
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
      valueToSum: valueToSum ?? this.valueToSum,
      revenueCurrency: revenueCurrency ?? this.revenueCurrency,
      sendToFacebook: sendToFacebook ?? this.sendToFacebook,
      sendToSingular: sendToSingular ?? this.sendToSingular,
      sendToCustomProviders:
          sendToCustomProviders ?? this.sendToCustomProviders,
    );
  }
}

/// Indicates that an analytics event is malformed.
class AnalyticsEventValidationException implements Exception {
  /// Creates an event validation error.
  const AnalyticsEventValidationException(this.message);

  /// Human-readable validation failure.
  final String message;

  @override
  String toString() => 'AnalyticsEventValidationException: $message';
}
