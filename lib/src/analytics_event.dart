class AnalyticsEvent {
  const AnalyticsEvent({
    required this.name,
    this.parameters = const <String, dynamic>{},
    this.valueToSum,
    this.revenueCurrency,
    this.sendToFacebook = true,
    this.sendToSingular = true,
  });

  final String name;
  final Map<String, dynamic> parameters;
  final double? valueToSum;
  final String? revenueCurrency;
  final bool sendToFacebook;
  final bool sendToSingular;

  bool get hasRevenue => valueToSum != null && revenueCurrency != null;

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'parameters': parameters,
      'value_to_sum': valueToSum,
      'revenue_currency': revenueCurrency,
      'send_to_facebook': sendToFacebook,
      'send_to_singular': sendToSingular,
    };
  }

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
    );
  }

  AnalyticsEvent copyWith({
    String? name,
    Map<String, dynamic>? parameters,
    double? valueToSum,
    String? revenueCurrency,
    bool? sendToFacebook,
    bool? sendToSingular,
  }) {
    return AnalyticsEvent(
      name: name ?? this.name,
      parameters: parameters ?? this.parameters,
      valueToSum: valueToSum ?? this.valueToSum,
      revenueCurrency: revenueCurrency ?? this.revenueCurrency,
      sendToFacebook: sendToFacebook ?? this.sendToFacebook,
      sendToSingular: sendToSingular ?? this.sendToSingular,
    );
  }
}

class AnalyticsEventValidationException implements Exception {
  const AnalyticsEventValidationException(this.message);

  final String message;

  @override
  String toString() => 'AnalyticsEventValidationException: $message';
}
