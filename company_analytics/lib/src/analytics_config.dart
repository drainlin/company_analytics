class AnalyticsConfig {
  const AnalyticsConfig({
    required this.singularApiKey,
    required this.singularSecret,
    this.enableFacebook = true,
    this.enableSingular = true,
    this.queueEventsBeforeInit = true,
    this.failFastOnTrackBeforeInit = false,
    this.facebookAutoLogAppEventsEnabled,
    this.facebookAdvertiserTrackingEnabled,
    this.singularEnableLogging = false,
    this.singularWaitForTrackingAuthSeconds = 0,
  });

  final String singularApiKey;
  final String singularSecret;

  final bool enableFacebook;
  final bool enableSingular;

  final bool queueEventsBeforeInit;
  final bool failFastOnTrackBeforeInit;

  final bool? facebookAutoLogAppEventsEnabled;
  final bool? facebookAdvertiserTrackingEnabled;

  final bool singularEnableLogging;
  final int singularWaitForTrackingAuthSeconds;

  List<String> validate({bool hasCustomProviders = false}) {
    final errors = <String>[];

    if (!hasCustomProviders && !enableFacebook && !enableSingular) {
      errors.add('At least one analytics provider must be enabled.');
    }

    if (enableSingular && singularApiKey.trim().isEmpty) {
      errors.add('Singular api key is required when Singular is enabled.');
    }

    if (enableSingular && singularSecret.trim().isEmpty) {
      errors.add('Singular secret is required when Singular is enabled.');
    }

    if (singularWaitForTrackingAuthSeconds < 0) {
      errors.add('Singular tracking auth timeout must be >= 0 seconds.');
    }

    return errors;
  }
}
