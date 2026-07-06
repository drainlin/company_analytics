## 0.0.8

* Remove the legacy manual `init(AnalyticsConfig)` public entrypoint.
* Remove the legacy YAML/native setup CLI and scripts.
* Keep remote JSON initialization as the only supported integration path.

## 0.0.7

* Add App Tracking Transparency support before Facebook and Singular native SDK initialization.
* Request ATT on iOS when the status is `notDetermined`.
* Document the required `NSUserTrackingUsageDescription` Info.plist entry.
* Export provider and tracking authorization extension points from the package entrypoint.
* Treat generated placeholder remote-config values as disabled Facebook or Singular providers.

## 0.0.6

* Raise minimum Flutter SDK to 3.38.0.
* Vendor facebook_app_events 0.30.2.
* Vendor singular_flutter_sdk 1.8.0 with Singular Android SDK 12.14.0 and iOS SDK 12.12.0.
* Add remote analytics JSON loading with successful-config caching.
* Add local development remote-config JSON and localhost serving script.
* Update documentation to make remote JSON configuration the primary integration path.

## 0.0.1

* TODO: Describe initial release.
