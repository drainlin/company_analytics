class AnalyticsNotInitializedException implements Exception {
  AnalyticsNotInitializedException(this.message);

  final String message;

  @override
  String toString() => 'AnalyticsNotInitializedException: $message';
}

class AnalyticsInitializationException implements Exception {
  AnalyticsInitializationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    if (cause == null) {
      return 'AnalyticsInitializationException: $message';
    }
    return 'AnalyticsInitializationException: $message; cause=$cause';
  }
}

class AnalyticsDeliveryException implements Exception {
  AnalyticsDeliveryException(this.eventName, this.providerErrors);

  final String eventName;
  final Map<String, Object> providerErrors;

  @override
  String toString() {
    return 'AnalyticsDeliveryException: event=$eventName; '
        'providerErrors=$providerErrors';
  }
}
