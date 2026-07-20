## 0.1.4

* Make remote or cached JSON authoritative over legacy native Facebook credentials.
* Delay Facebook App Events startup until Dart has resolved its runtime configuration.
* Allow a new Facebook app id and client token to replace values left by older SDK versions.
* Bind Android and iOS App Events explicitly to the runtime Facebook app id.

## 0.1.3

* Configure Facebook auto-log and advertiser-id flags atomically with native SDK startup.
* Restore early native Facebook initialization when platform credentials are present.
* Recover the initial Android activation when runtime initialization happens after resume.
* Map shared event names to Meta standard events and use the native Purchase API.
* Isolate provider delivery failures and retain failed queued events for retry.
* Persist the pre-initialization event outbox and serialize concurrent queue operations.
* Validate event revenue fields before queueing or delivery.
* Bound the persistent outbox and batch its drain writes.
* Await Singular platform calls so native delivery errors reach retry handling.
* Preserve an explicitly disabled native Facebook auto-log setting on iOS.
* Serialize concurrent analytics initialization attempts.
* Remove production codeless debug logging and pin the Meta native SDK versions.
* Update the vendored Singular Android plugin for AGP 9 and Maven Central.

## 0.1.2

* Increase the default remote config timeout to 15 seconds.
* Print remote config request failures and cache fallback status.

## 0.1.1

* Print Facebook app id and client token after test-mode initialization.
* Flush Facebook events immediately when test mode is enabled.

## 0.1.0

* Add a runtime Facebook test mode flag for `initFromRemoteConfig()`.
* Improve revenue event tracking behavior.

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
