class AnalyticsConfig {
  const AnalyticsConfig({
    required this.singularApiKey,
    required this.singularSecret,
    this.facebookAppId,
    this.facebookClientToken,
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
  final String? facebookAppId;
  final String? facebookClientToken;

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

    final shouldValidateDefaultProviders = !hasCustomProviders;

    if (shouldValidateDefaultProviders &&
        enableFacebook &&
        (facebookAppId == null || facebookAppId!.trim().isEmpty)) {
      errors.add('Facebook app id is required when Facebook is enabled.');
    }

    if (shouldValidateDefaultProviders &&
        enableFacebook &&
        (facebookClientToken == null || facebookClientToken!.trim().isEmpty)) {
      errors.add('Facebook client token is required when Facebook is enabled.');
    }

    if (shouldValidateDefaultProviders &&
        enableSingular &&
        singularApiKey.trim().isEmpty) {
      errors.add('Singular api key is required when Singular is enabled.');
    }

    if (shouldValidateDefaultProviders &&
        enableSingular &&
        singularSecret.trim().isEmpty) {
      errors.add('Singular secret is required when Singular is enabled.');
    }

    if (singularWaitForTrackingAuthSeconds < 0) {
      errors.add('Singular tracking auth timeout must be >= 0 seconds.');
    }

    return errors;
  }
}
