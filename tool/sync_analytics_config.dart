import 'dart:io';

import 'package:yaml/yaml.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _usageAndExit('Missing required args.');
  }

  String? appRoot;
  String? yamlPath;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--app-root' && i + 1 < args.length) {
      appRoot = args[++i];
      continue;
    }
    if (arg == '--config' && i + 1 < args.length) {
      yamlPath = args[++i];
      continue;
    }
  }

  if (appRoot == null || yamlPath == null) {
    _usageAndExit('Both --app-root and --config are required.');
  }

  final appRootDir = Directory(appRoot);
  if (!appRootDir.existsSync()) {
    _fail('App root does not exist: $appRoot');
  }

  final configFile = File(yamlPath);
  if (!configFile.existsSync()) {
    _fail('YAML config not found: $yamlPath');
  }

  final yaml = loadYaml(configFile.readAsStringSync());
  if (yaml is! YamlMap) {
    _fail('Invalid yaml structure. Root must be a map.');
  }

  final facebook = yaml['facebook'];
  if (facebook is! YamlMap) {
    _fail('Missing facebook section in yaml.');
  }

  final singular = yaml['singular'];
  if (singular is! YamlMap) {
    _fail('Missing singular section in yaml.');
  }

  final String iosFacebookAppId = _readRequiredPlatformOrLegacyString(
    section: facebook,
    platform: 'ios',
    key: 'app_id',
    legacyKey: 'app_id',
    keyForError: 'facebook.ios.app_id (or legacy facebook.app_id)',
  );
  final String iosFacebookClientToken = _readRequiredPlatformOrLegacyString(
    section: facebook,
    platform: 'ios',
    key: 'client_token',
    legacyKey: 'client_token',
    keyForError: 'facebook.ios.client_token (or legacy facebook.client_token)',
  );
  final String iosFacebookDisplayName =
      _readOptionalPlatformOrLegacyString(
        section: facebook,
        platform: 'ios',
        key: 'display_name',
        legacyKey: 'display_name',
      ) ??
      'App';

  final String androidFacebookAppId = _readRequiredPlatformOrLegacyString(
    section: facebook,
    platform: 'android',
    key: 'app_id',
    legacyKey: 'app_id',
    keyForError: 'facebook.android.app_id (or legacy facebook.app_id)',
  );
  final String androidFacebookClientToken = _readRequiredPlatformOrLegacyString(
    section: facebook,
    platform: 'android',
    key: 'client_token',
    legacyKey: 'client_token',
    keyForError:
        'facebook.android.client_token (or legacy facebook.client_token)',
  );
  final String androidFacebookDisplayName =
      _readOptionalPlatformOrLegacyString(
        section: facebook,
        platform: 'android',
        key: 'display_name',
        legacyKey: 'display_name',
      ) ??
      iosFacebookDisplayName;

  final String iosSingularApiKey = _readRequiredPlatformOrLegacyString(
    section: singular,
    platform: 'ios',
    key: 'api_key',
    legacyKey: 'api_key',
    keyForError: 'singular.ios.api_key (or legacy singular.api_key)',
  );
  final String iosSingularSecret = _readRequiredPlatformOrLegacyString(
    section: singular,
    platform: 'ios',
    key: 'secret',
    legacyKey: 'secret',
    keyForError: 'singular.ios.secret (or legacy singular.secret)',
  );
  final String androidSingularApiKey = _readRequiredPlatformOrLegacyString(
    section: singular,
    platform: 'android',
    key: 'api_key',
    legacyKey: 'api_key',
    keyForError: 'singular.android.api_key (or legacy singular.api_key)',
  );
  final String androidSingularSecret = _readRequiredPlatformOrLegacyString(
    section: singular,
    platform: 'android',
    key: 'secret',
    legacyKey: 'secret',
    keyForError: 'singular.android.secret (or legacy singular.secret)',
  );

  _writeAndroidFiles(
    appRootDir,
    appId: androidFacebookAppId,
    clientToken: androidFacebookClientToken,
  );
  _writeIosFiles(
    appRootDir,
    appId: iosFacebookAppId,
    clientToken: iosFacebookClientToken,
    displayName: iosFacebookDisplayName,
  );
  _writeDartEnvFile(
    appRootDir,
    iosFacebookAppId: iosFacebookAppId,
    iosFacebookClientToken: iosFacebookClientToken,
    iosFacebookDisplayName: iosFacebookDisplayName,
    androidFacebookAppId: androidFacebookAppId,
    androidFacebookClientToken: androidFacebookClientToken,
    androidFacebookDisplayName: androidFacebookDisplayName,
    iosSingularApiKey: iosSingularApiKey,
    iosSingularSecret: iosSingularSecret,
    androidSingularApiKey: androidSingularApiKey,
    androidSingularSecret: androidSingularSecret,
  );

  stdout.writeln('Done. Analytics native/dart config generated successfully.');
  stdout.writeln(
    'Next: run check script: bash tool/check_facebook_setup.sh ${appRootDir.path}',
  );
}

void _writeAndroidFiles(
  Directory appRoot, {
  required String appId,
  required String clientToken,
}) {
  final androidValuesDir = Directory(
    '${appRoot.path}/android/app/src/main/res/values',
  );
  androidValuesDir.createSync(recursive: true);

  final facebookXml = File('${androidValuesDir.path}/facebook_config.xml');
  facebookXml.writeAsStringSync('''<?xml version="1.0" encoding="utf-8"?>
<resources>
  <string name="facebook_app_id">$appId</string>
  <string name="facebook_client_token">$clientToken</string>
  <string name="fb_login_protocol_scheme">fb$appId</string>
</resources>
''');

  stdout.writeln('Wrote ${facebookXml.path}');
}

void _writeIosFiles(
  Directory appRoot, {
  required String appId,
  required String clientToken,
  required String displayName,
}) {
  final iosFlutterDir = Directory('${appRoot.path}/ios/Flutter');
  iosFlutterDir.createSync(recursive: true);

  final fbConfig = File('${iosFlutterDir.path}/FacebookConfig.xcconfig');
  fbConfig.writeAsStringSync(
    '''// Generated by company_analytics/tool/sync_analytics_config.dart
FACEBOOK_APP_ID=$appId
FACEBOOK_CLIENT_TOKEN=$clientToken
FACEBOOK_DISPLAY_NAME=$displayName
''',
  );

  _ensureInclude('${iosFlutterDir.path}/Debug.xcconfig');
  _ensureInclude('${iosFlutterDir.path}/Release.xcconfig');
  _ensureInclude('${iosFlutterDir.path}/Profile.xcconfig');

  stdout.writeln('Wrote ${fbConfig.path}');
  stdout.writeln(
    'Ensured FacebookConfig.xcconfig include in iOS xcconfig files.',
  );
  stdout.writeln(
    'Reminder: Info.plist should use \$(FACEBOOK_APP_ID), \$(FACEBOOK_CLIENT_TOKEN), and fb\$(FACEBOOK_APP_ID).',
  );
}

void _writeDartEnvFile(
  Directory appRoot, {
  required String iosFacebookAppId,
  required String iosFacebookClientToken,
  required String iosFacebookDisplayName,
  required String androidFacebookAppId,
  required String androidFacebookClientToken,
  required String androidFacebookDisplayName,
  required String iosSingularApiKey,
  required String iosSingularSecret,
  required String androidSingularApiKey,
  required String androidSingularSecret,
}) {
  final dartOutDir = Directory('${appRoot.path}/lib/generated');
  dartOutDir.createSync(recursive: true);

  final envFile = File('${dartOutDir.path}/analytics_env.g.dart');
  envFile.writeAsStringSync('''// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by company_analytics/tool/sync_analytics_config.dart

class AnalyticsEnv {
  static const String facebookIosAppId = '$iosFacebookAppId';
  static const String facebookIosClientToken = '$iosFacebookClientToken';
  static const String facebookIosDisplayName = '$iosFacebookDisplayName';

  static const String facebookAndroidAppId = '$androidFacebookAppId';
  static const String facebookAndroidClientToken =
      '$androidFacebookClientToken';
  static const String facebookAndroidDisplayName = '$androidFacebookDisplayName';

  static const String singularIosApiKey = '$iosSingularApiKey';
  static const String singularIosSecret = '$iosSingularSecret';
  static const String singularAndroidApiKey = '$androidSingularApiKey';
  static const String singularAndroidSecret = '$androidSingularSecret';

  // Backward-compatible aliases (default to iOS values).
  static const String facebookAppId = facebookIosAppId;
  static const String facebookClientToken = facebookIosClientToken;
  static const String facebookDisplayName = facebookIosDisplayName;
  static const String singularApiKey = singularIosApiKey;
  static const String singularSecret = singularIosSecret;
}
''');

  stdout.writeln('Wrote ${envFile.path}');
}

void _ensureInclude(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return;
  }

  final includeLine = '#include? "FacebookConfig.xcconfig"';
  final content = file.readAsStringSync();

  if (!content.contains(includeLine)) {
    final newContent = '$includeLine\n$content';
    file.writeAsStringSync(newContent);
  }
}

String _readRequiredPlatformOrLegacyString({
  required YamlMap section,
  required String platform,
  required String key,
  required String legacyKey,
  required String keyForError,
}) {
  final String? platformValue = _readOptionalPlatformString(
    section: section,
    platform: platform,
    key: key,
  );
  if (platformValue != null) {
    return platformValue;
  }

  final String? legacyValue = _readOptionalLegacyString(
    section: section,
    key: legacyKey,
  );
  if (legacyValue != null) {
    return legacyValue;
  }

  _fail('Missing required key: $keyForError');
}

String? _readOptionalPlatformOrLegacyString({
  required YamlMap section,
  required String platform,
  required String key,
  required String legacyKey,
}) {
  final String? platformValue = _readOptionalPlatformString(
    section: section,
    platform: platform,
    key: key,
  );
  if (platformValue != null) {
    return platformValue;
  }

  return _readOptionalLegacyString(section: section, key: legacyKey);
}

String? _readOptionalPlatformString({
  required YamlMap section,
  required String platform,
  required String key,
}) {
  final dynamic scoped = section[platform];
  if (scoped is! YamlMap) {
    return null;
  }
  final dynamic value = scoped[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _readOptionalLegacyString({
  required YamlMap section,
  required String key,
}) {
  final dynamic value = section[key];
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

Never _fail(String message) {
  stderr.writeln('ERROR: $message');
  exit(1);
}

Never _usageAndExit(String message) {
  stderr.writeln(message);
  stderr.writeln('Usage:');
  stderr.writeln(
    '  dart run tool/sync_analytics_config.dart --app-root <flutter_app_root> --config <yaml_path>',
  );
  exit(2);
}
