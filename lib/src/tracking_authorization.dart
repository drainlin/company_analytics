import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';

abstract class TrackingAuthorizationRequester {
  Future<void> requestIfNeeded();
}

class AppTrackingTransparencyRequester
    implements TrackingAuthorizationRequester {
  AppTrackingTransparencyRequester({TargetPlatform? platform})
    : _platform = platform;

  final TargetPlatform? _platform;

  @override
  Future<void> requestIfNeeded() async {
    if ((_platform ?? defaultTargetPlatform) != TargetPlatform.iOS) {
      return;
    }

    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status != TrackingStatus.notDetermined) {
      return;
    }

    await AppTrackingTransparency.requestTrackingAuthorization();
  }
}
