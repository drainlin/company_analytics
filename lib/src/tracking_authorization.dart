import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';

/// Requests platform tracking authorization before native analytics SDK startup.
abstract class TrackingAuthorizationRequester {
  /// Requests tracking authorization if the current platform and status require it.
  Future<void> requestIfNeeded();
}

/// ATT-backed implementation used by [CompanyAnalytics] on iOS.
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
