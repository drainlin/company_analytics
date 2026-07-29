import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('configure defaults debug logging to !kReleaseMode', () async {
    MethodCall? recordedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    await FacebookAppEvents().configure(
      appId: 'app-id',
      clientToken: 'client-token',
    );

    expect(recordedCall?.method, 'configure');
    expect(
      (recordedCall?.arguments as Map<Object?, Object?>)['debugLoggingEnabled'],
      !kReleaseMode,
    );
  });

  test('configure preserves an explicit debug logging value', () async {
    MethodCall? recordedCall;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recordedCall = call;
      return null;
    });

    await FacebookAppEvents().configure(
      appId: 'app-id',
      clientToken: 'client-token',
      debugLoggingEnabled: false,
    );

    expect(
      (recordedCall?.arguments as Map<Object?, Object?>)['debugLoggingEnabled'],
      isFalse,
    );
  });
}
