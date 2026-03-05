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
