# company_analytics 开发文档

这个包是项目内统一埋点入口，封装仓库内置的 Facebook App Events 和 Singular Flutter SDK。

当前主流程以运行时远程配置为准：Facebook 凭据和自动采集开关从远程 JSON 加载，远程失败时使用上一次成功缓存；Singular 凭据同样由远程配置下发。Facebook 不再依赖宿主原生工程中的预置值启动。

## 环境要求

- Dart: `>=3.10.0 <4.0.0`
- Flutter: `>=3.38.0`
- Facebook App Events Flutter SDK: 仓库内补丁版本 `0.30.2+company.3`
- Singular Flutter SDK: 仓库内补丁版本 `1.8.0+company.3`
  - Android Singular SDK: `12.14.0`
  - iOS Singular SDK: `12.12.0`
- App Tracking Transparency Flutter SDK: `^2.0.7`
- In App Purchase Flutter SDK: `3.2.4`

## 远程配置服务

线上联调使用 远程配置服务：

- 示例配置 URL：`https://config.example.com/event_manager/analytics.remote.json`

公开 JSON URL 格式：

```text
https://config.example.com/<app>/<file>.json
```

规则：

- 左侧选择 app。
- 右侧选择 JSON 文件。
- `analytics.remote.json` 使用表单编辑。
- 不存在的 app 或 JSON 文件返回 `404`。
- 改名 app 或 JSON 文件后，旧路径返回 `404`，新路径返回 `200`。

## 本地远程配置服务

开发期编辑：

- [analytics.remote.dev.json](/Users/yulin/Projects/event_manager/config/analytics.remote.dev.json)

启动服务：

```bash
bash tool/serve_remote_config.sh
```

访问地址：

- iOS Simulator / desktop: `http://127.0.0.1:8765/analytics.remote.dev.json`
- Android Emulator: `http://10.0.2.2:8765/analytics.remote.dev.json`

校验当前服务内容：

```bash
curl -fsS http://127.0.0.1:8765/analytics.remote.dev.json
```

## JSON 结构

配置放在同一个 JSON 文件里，用 `ios` 和 `android` 字段区分平台：

```json
{
  "version": 1,
  "enable_facebook": true,
  "enable_singular": true,
  "facebook": {
    "ios": {
      "app_id": "YOUR_FACEBOOK_APP_ID_IOS",
      "client_token": "YOUR_FACEBOOK_CLIENT_TOKEN_IOS"
    },
    "android": {
      "app_id": "YOUR_FACEBOOK_APP_ID_ANDROID",
      "client_token": "YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID"
    },
    "auto_log_app_events_enabled": true,
    "advertiser_tracking_enabled": true
  },
  "singular": {
    "ios": {
      "api_key": "YOUR_SINGULAR_API_KEY_IOS",
      "secret": "YOUR_SINGULAR_SECRET_IOS"
    },
    "android": {
      "api_key": "YOUR_SINGULAR_API_KEY_ANDROID",
      "secret": "YOUR_SINGULAR_SECRET_ANDROID"
    },
    "enable_logging": true,
    "wait_for_tracking_auth_seconds": 15
  }
}
```

字段说明：

- `version`: 配置版本，写入缓存 metadata，便于排查。
- `enable_facebook`: 是否启用 Facebook provider。
- `enable_singular`: 是否启用 Singular provider。
- `facebook.ios/android.app_id`: 当前平台 Facebook app id。
- `facebook.ios/android.client_token`: 当前平台 Facebook client token。
- `facebook.auto_log_app_events_enabled`: 传给 Facebook SDK 的自动事件开关。
- `facebook.advertiser_tracking_enabled`: 传给 Facebook SDK 的 advertiser tracking 开关。
- `singular.ios/android.api_key`: 当前平台 Singular api key。
- `singular.ios/android.secret`: 当前平台 Singular secret。
- `singular.enable_logging`: Singular 日志开关，生产环境建议关闭。
- `singular.wait_for_tracking_auth_seconds`: Singular 等待 ATT 授权的秒数。

## 初始化流程

业务侧推荐只调用 `initFromRemoteConfig()`。iOS 会在这个流程内请求 ATT，因此业务侧应在首屏渲染后或自定义 ATT 说明弹窗后调用，不要在 `runApp()` 之前等待系统弹窗。若合规策略要求禁用自动采集，应在远程 JSON 中把 Facebook auto-log 和 advertiser ID collection 显式设为 `false`。

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:flutter/foundation.dart';

final analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
  await analytics.initFromRemoteConfig(
    RemoteAnalyticsConfig(
      url: Uri.parse(
        'https://config.example.com/event_manager/analytics.remote.json',
      ),
      timeout: const Duration(seconds: 15),
      useCachedConfigOnFailure: true,
    ),
    debugLoggingEnabled: kDebugMode,
  );
}
```

`debugLoggingEnabled` 是推荐参数，会统一开启：

- Facebook 的 `debugLoggingEnabled`
- Singular 的 `enableLogging`
- 本包内的 tracking 调试日志（事件分发、排队、provider 调用）

如需只控制 Facebook 日志，可使用 `facebookDebugLoggingEnabled`。它与
`facebookTestModeEnabled` 是同一兼容层，未显式传值时仍采用 `!kReleaseMode`
（Debug/Profile 开启，Release 关闭）。

`debugLoggingEnabled` 未显式传值时，默认也按 `!kReleaseMode`
作为统一开关，Debug/Profile 默认会同时开启 Singular 与 tracking 日志。

初始化顺序：

1. `RemoteAnalyticsConfigLoader` 请求 URL。
2. 按当前平台解析 JSON。
3. 校验 `AnalyticsConfig`。
4. Facebook 等待 Dart 解析运行时凭据，不使用宿主残留的原生凭据提前启动。
5. iOS 检查 ATT 状态；如果是 `notDetermined`，先请求系统 ATT 权限。
6. Facebook provider 原子传入 app id、client token、auto-log 和 advertiser ID collection 配置；延迟初始化路径会在需要时补记当前 activation。
7. Singular provider 使用 runtime key/secret 初始化。
8. 初始化前缓存的事件开始补发。

远程请求默认最多尝试 3 次：

```dart
RemoteAnalyticsConfig(
  url: Uri.parse(
    'https://config.example.com/event_manager/analytics.remote.json',
  ),
  timeout: const Duration(seconds: 15),
  maxAttempts: 3,
  retryDelay: const Duration(milliseconds: 500),
  retryBackoffMultiplier: 2,
  useCachedConfigOnFailure: true,
)
```

如果所有远程请求都失败，会再尝试读取上一次成功缓存。没有缓存时才抛出 `AnalyticsInitializationException`。

如果启动阶段初始化失败，`CompanyAnalytics` 会保留最近一次
`RemoteAnalyticsConfig` 和 loader。后续可排队的 Singular 固定事件或自定义
事件会先立即重试远程初始化；重试成功后上报当前事件，重试失败则按原策略排队，
或在 fail-fast 模式下抛 `AnalyticsNotInitializedException`。带购买验证数据的
`trackSingularInAppPurchase()` 不写入 SharedPreferences，未初始化时直接抛错。

## 缓存与变更检测

远程请求成功后会缓存原始 JSON 和 metadata。远程失败时，如果 `useCachedConfigOnFailure` 为 `true`，会回退到上一次成功缓存。

```dart
final loader = RemoteAnalyticsConfigLoader();
final remoteConfig = RemoteAnalyticsConfig(
  url: Uri.parse(
    'https://config.example.com/event_manager/analytics.remote.json',
  ),
);

final result = await loader.loadResult(remoteConfig);

print(result.source); // RemoteAnalyticsConfigSource.remote/cache
print(result.changedFromCache);
print(result.metadata?.version);
print(result.metadata?.sha256);
print(result.previousMetadata?.sha256);
```

`changedFromCache` 的语义：

- 本次远程请求成功，且已有缓存 metadata，并且新旧 `sha256` 不同：`true`
- 首次成功拉取，没有旧缓存：`false`
- 远程失败，使用缓存：`false`

清理缓存：

```dart
await loader.clearCache(remoteConfig);
```

## 平台配置原则

Facebook app id、client token、`AutoLogAppEventsEnabled` 和 advertiser ID collection 开关只以远程或缓存 JSON 为准。Android 会移除 Meta manifest auto-init provider；iOS 会等 Dart 配置完成后再启动 CoreKit。旧 SDK 留下的原生 Facebook 值不会覆盖新 JSON，也不会触发凭据不一致错误。

这个设计不保证 JSON 完成前的最早自动事件，保证的是设备成功缓存新配置后，后续冷启动会用远程配置（失败时用缓存）初始化 Facebook。URL scheme、Facebook Login/deep link 等构建期能力不在此保证内，换 app id 时仍需随应用发版更新。

Singular api key 和 secret 仍只由远程配置下发。

仍需保留 SDK 正常运行需要的平台能力配置，例如：

- iOS `NSUserTrackingUsageDescription` 权限说明；ATT 请求流程由本包在 SDK 初始化前执行
- iOS/Android deep link 或 URL scheme 能力，如果业务场景需要
- Android install referrer
- Android Proguard / R8 保留规则

## 事件上报

订阅购买成功，只发 Singular：

```dart
await analytics.trackSingularSubscription(
  amount: 9.99,
  currency: 'USD',
  subscriptionId: 'vip_monthly',
  transactionId: 'transaction_123',
);
```

免费试用开始，只发 Singular 且不带收入：

```dart
await analytics.trackSingularTrialStart(
  transactionId: 'transaction_123',
);
```

非订阅 IAP，只发 Singular：

```dart
await analytics.trackSingularInAppPurchase(
  purchase: purchaseDetails,
  product: productDetails,
);
```

这个方法使用 `sng_ecommerce_purchase`，根据平台从购买对象中提取 StoreKit
receipt 或 Google Play `originalJson/signature`。只接受
`PurchaseStatus.purchased`；不会完成或确认商店交易。

特殊自定义事件必须显式选择目标：

```dart
await analytics.trackCustomEvent(
  name: 'special_campaign_event',
  parameters: const <String, dynamic>{'campaign_id': 'summer_2026'},
  targets: const <AnalyticsTarget>{AnalyticsTarget.singular},
);
```

Facebook 的正常事件和购买事件由 Meta SDK 自动记录。除经过确认的特殊场景外，
不要把 `AnalyticsTarget.facebook` 加入自定义事件。

登录态：

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 初始化前事件策略

默认策略：订阅、试用和自定义事件在 `initFromRemoteConfig()` 完成前被调用时，
会写入 SharedPreferences 持久队列，初始化成功后补发。事件只有在所有目标
provider 成功后才出队；单个 provider 失败时其他 provider 仍会继续发送，并抛出
`AnalyticsDeliveryException` 供业务监控。队列采用 at-least-once 语义，
收入事件应使用稳定交易 ID 去重。默认上限为 200 条，超限丢弃最旧事件并记录在
`droppedPendingEventCount`；补发出队采用单次批量持久化，避免逐条全量重写。

非订阅 IAP 的 receipt/signature 不进入 SharedPreferences outbox，调用前必须
初始化成功。

严格模式：

```dart
final analytics = CompanyAnalytics(failFastBeforeInit: true);
```

## 排查顺序

初始化失败：

1. 确认 URL 能访问，并返回合法 JSON。
2. 确认当前平台分支存在，例如 iOS 有 `facebook.ios` 和 `singular.ios`。
3. 确认启用的 provider 对应字段非空。
4. 查看 `AnalyticsInitializationException` 的 inner error。
5. 查看 `analytics.lastRemoteConfigResult` 或 `RemoteAnalyticsConfigLoader.loadResult()`。

事件没有上报：

1. 确认 `initFromRemoteConfig()` 已成功完成。
2. 自定义事件确认 `targets` 包含预期渠道。
3. 调试环境打开 `singular.enable_logging`。
4. 检查 Facebook / Singular 平台侧必要能力配置。

远程配置没有生效：

1. 确认服务返回的是最新 JSON。
2. 查看 `result.source` 是否为 `remote`。
3. 查看 `result.changedFromCache` 和 `sha256`。
4. 必要时调用 `clearCache()` 后重启应用。

## 对外 API

`package:company_analytics/company_analytics.dart` 导出：

- `CompanyAnalytics`
- `AnalyticsEvent`
- `AnalyticsTarget`
- `AnalyticsProvider`
- `RemoteAnalyticsConfig`
- `RemoteAnalyticsConfigLoader`
- `RemoteAnalyticsConfigResult`
- `RemoteAnalyticsConfigMetadata`
- `RemoteAnalyticsConfigSource`
- `AnalyticsInitializationException`
- `AnalyticsNotInitializedException`
- `InMemoryAnalyticsProvider`

`track(AnalyticsEvent)`、`AnalyticsSdkSingletons.facebookAppEvents` 和
`AnalyticsSdkSingletons.singular` 仍保留，但已标记 `@Deprecated`。业务代码应
优先使用三个固定 Singular 方法或带显式 targets 的 `trackCustomEvent()`。

## 旧接入方式

旧 YAML / 原生预填脚本和手动 `init(AnalyticsConfig)` 入口已移除。当前只保留远程 JSON 初始化路径。

## 开发校验

修改插件后至少运行：

```bash
flutter analyze
flutter test
```
