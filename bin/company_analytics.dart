import 'dart:isolate';
import 'dart:io';

void main(List<String> args) async {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _printHelp();
    exit(0);
  }

  final String command = args.first;
  final List<String> rest = args.sublist(1);
  final String packageRoot = await _resolvePackageRoot();

  final String scriptPath;
  final List<String> scriptArgs;

  switch (command) {
    case 'setup':
      scriptPath = '$packageRoot/tool/setup_analytics.sh';
      scriptArgs = _normalizeAppRoot(rest);
      break;
    case 'sync':
      scriptPath = '$packageRoot/tool/sync_analytics_config.sh';
      scriptArgs = _normalizeAppRoot(rest);
      break;
    case 'apply':
      scriptPath = '$packageRoot/tool/apply_native_templates.sh';
      scriptArgs = _normalizePositionalAppRoot(rest);
      break;
    case 'check':
      scriptPath = '$packageRoot/tool/check_facebook_setup.sh';
      scriptArgs = _normalizePositionalAppRoot(rest);
      break;
    default:
      stderr.writeln('Unknown command: $command');
      _printHelp();
      exit(2);
  }

  final File scriptFile = File(scriptPath);
  if (!scriptFile.existsSync()) {
    stderr.writeln('Script not found: $scriptPath');
    exit(1);
  }

  final Process process = await Process.start('bash', <String>[
    scriptPath,
    ...scriptArgs,
  ], mode: ProcessStartMode.inheritStdio);

  final int exitCode = await process.exitCode;
  exit(exitCode);
}

List<String> _normalizeAppRoot(List<String> args) {
  if (_hasFlag(args, '--app-root')) {
    return args;
  }
  return <String>['--app-root', '.', ...args];
}

List<String> _normalizePositionalAppRoot(List<String> args) {
  if (args.isEmpty) {
    return <String>['.'];
  }

  if (_hasFlag(args, '--app-root')) {
    final int index = args.indexOf('--app-root');
    if (index >= 0 && index + 1 < args.length) {
      return <String>[args[index + 1]];
    }
  }
  return args;
}

bool _hasFlag(List<String> args, String flag) {
  return args.contains(flag);
}

void _printHelp() {
  stdout.writeln('company_analytics CLI');
  stdout.writeln('');
  stdout.writeln('Usage:');
  stdout.writeln(
    '  dart run company_analytics:company_analytics <command> [options]',
  );
  stdout.writeln('');
  stdout.writeln('Commands:');
  stdout.writeln('  setup   Run setup_analytics.sh');
  stdout.writeln('  sync    Run sync_analytics_config.sh');
  stdout.writeln('  apply   Run apply_native_templates.sh');
  stdout.writeln('  check   Run check_facebook_setup.sh');
  stdout.writeln('');
  stdout.writeln('Examples:');
  stdout.writeln(
    '  dart run company_analytics:company_analytics setup --app-root .',
  );
  stdout.writeln(
    '  dart run company_analytics:company_analytics sync --app-root .',
  );
  stdout.writeln('  dart run company_analytics:company_analytics apply .');
  stdout.writeln('  dart run company_analytics:company_analytics check .');
}

Future<String> _resolvePackageRoot() async {
  final Uri? libUri = await Isolate.resolvePackageUri(
    Uri.parse('package:company_analytics/company_analytics.dart'),
  );
  if (libUri == null) {
    stderr.writeln(
      'Unable to resolve package root for company_analytics package.',
    );
    exit(1);
  }

  return File.fromUri(libUri).parent.parent.path;
}
