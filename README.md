# company_analytics

`company_analytics` 是项目内统一埋点入口，封装仓库内置的 Facebook App Events 和 Singular Flutter SDK。

当前推荐方案：Facebook app id 和 client token 同时写入宿主原生配置与远程 JSON，使 Meta SDK 能在首个生命周期回调前启动，并让 Dart provider 校验两端凭据一致。Facebook 自动事件开关也建议写入原生配置；远程 JSON 可显式覆盖，省略时保留原生值。Singular key 继续由远程 JSON 下发。

没有原生 Facebook 配置时仍支持运行时初始化，但只能作为兼容路径：Android 会补记已处于前台的首次 activation，iOS 会在 CoreKit 初始化后应用运行时凭据。对自动生命周期、无代码事件和最早发生的 IAP，原生启动期配置仍然最可靠。

## 版本要求

- Dart: `>=3.8.1 <4.0.0`
- Flutter: `>=3.38.0`
- Facebook App Events Flutter SDK: 仓库内补丁版本 `0.30.2+company.1`
- Singular Flutter SDK: 仓库内补丁版本 `1.8.0+company.2`
  - Android Singular SDK: `12.14.0`
  - iOS Singular SDK: `12.12.0`
- App Tracking Transparency Flutter SDK: `^2.0.7`

## 安装

Git 依赖：

```yaml
dependencies:
  company_analytics:
    git:
      url: http://git.qisoft.cn/dengyulin/company_analytics.git
      ref: v0.1.3
```

本地开发依赖：

```yaml
dependencies:
  company_analytics:
    path: ../company_analytics
```

执行：

```bash
flutter pub get
```

## 远程配置

生产/联调推荐使用已部署的远程配置服务维护 JSON：

- 示例配置 URL：`https://config.example.com/event_manager/analytics.remote.json`

后台支持：

- 新增 / 改名 app
- 新增 / 改名 / 删除 JSON 文件
- 使用表单编辑 `analytics.remote.json`
- 通过高级 JSON 预览查看最终配置

公开 JSON URL 使用固定格式：

```text
https://config.example.com/<app>/<file>.json
```

不存在的 app 或 JSON 文件会返回 `404`。

本地开发也可以编辑仓库内的本地 JSON：

- [analytics.remote.dev.json](/Users/yulin/Projects/event_manager/config/analytics.remote.dev.json)

启动本地配置服务：

```bash
bash tool/serve_remote_config.sh
```

本地 URL：

- iOS Simulator / desktop: `http://127.0.0.1:8765/analytics.remote.dev.json`
- Android Emulator: `http://10.0.2.2:8765/analytics.remote.dev.json`

JSON 使用同一个文件，并在文件内区分 iOS 和 Android：

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

模板里的 `YOUR_...` 占位值会被视为“未配置”。如果当前平台的 Facebook 或 Singular 必填值仍是这些默认占位值，即使对应的 `enable_*` 为 `true`，SDK 也会把该 provider 当作未开启处理，不会启动对应原生 SDK。

Facebook 可选开关的解析规则：

| 远程字段 | 省略时 | 显式传值时 |
| --- | --- | --- |
| `auto_log_app_events_enabled` | 保留原生 `FacebookAutoLogAppEventsEnabled`；原生也未配置时使用 Meta 默认值 `true` | 覆盖当前原生 SDK 设置 |
| `advertiser_tracking_enabled` | 保留原生 `FacebookAdvertiserIDCollectionEnabled` | 覆盖当前原生 SDK 设置 |

iOS 原生 auto-log 明确为 `false` 且远程字段省略时，SDK 不会主动调用 `activateApp()`。如果合规策略要求 ATT 状态确定前不采集，请把两个原生开关设为 `false`；远程配置也设为 `false` 或省略 auto-log，除非你明确希望在 ATT 检查完成后重新启用。

每次启动会先请求远程 URL；成功解析后写入本地缓存。网络失败时会使用上一次成功解析的缓存。缓存 metadata 包含 `version`、`sha256`、`source_url`、`cached_at`。

远程请求默认最多尝试 3 次，每次请求默认超时 15 秒，重试间隔从 500ms 开始退避。如果所有远程请求都失败，再按 `useCachedConfigOnFailure` 决定是否使用缓存。

## 初始化

建议在首屏渲染后或业务自定义 ATT 说明弹窗后调用 Dart 初始化。iOS 会在 `initFromRemoteConfig()` 内部请求 ATT，因此不要在 `runApp()` 之前等待系统弹窗。若宿主预置了 Facebook 原生凭据，CoreKit 会提前完成基础启动；需要严格等到 ATT 状态确定后才采集时，请把原生 `FacebookAutoLogAppEventsEnabled` 和 `FacebookAdvertiserIDCollectionEnabled` 都设为 `false`。远程配置显式设为 `true` 会在 ATT 检查结束后启用并补记当前 activation，不会区分用户最终是授权还是拒绝，因此必须由你们的合规策略决定是否启用。

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:flutter/foundation.dart';

final CompanyAnalytics analytics = CompanyAnalytics(
  maxPendingEvents: 200,
);

Future<void> initAnalytics() async {
  await analytics.initFromRemoteConfig(
    RemoteAnalyticsConfig(
      url: Uri.parse(
        'https://config.example.com/event_manager/analytics.remote.json',
      ),
      timeout: const Duration(seconds: 15),
      maxAttempts: 3,
      retryDelay: const Duration(milliseconds: 500),
      useCachedConfigOnFailure: true,
    ),
    facebookTestModeEnabled: kDebugMode,
  );
}
```

`facebookTestModeEnabled` 是本地运行时参数，不属于远程 JSON。调试时可设为 `true`，用于打开 Facebook SDK 的测试/调试日志；生产环境保持默认 `false`。

如果启动时因为网络或无缓存导致 `initFromRemoteConfig()` 初始化失败，`CompanyAnalytics` 会记住这次远程配置参数。后续第一次 `track()` 发现还没初始化时，会先立即重试远程初始化；重试成功后再上报当前事件，重试失败则继续按原策略排队或 fail-fast。

### 持久 outbox

初始化前事件会写入 `SharedPreferences` 持久 outbox。应用进程退出后事件仍会保留；初始化或后续 `track()` 会按顺序补发，只有所有目标 provider 都成功后才删除。单个 provider 失败不会阻止其他 provider 接收当前事件，失败的队首事件会留待下次重试。

- 默认上限为 200 条，可通过 `CompanyAnalytics(maxPendingEvents: ...)` 调整。
- 超限时丢弃最旧事件，并增加 `droppedPendingEventCount`。
- 一轮补发结束或遇到失败时只批量落盘一次，避免逐条重写整个队列。
- 采用 at-least-once 语义：部分 provider 成功后重试时可能重复收到事件，收入事件应携带稳定订单 ID 供服务端去重。
- 已初始化后直接上报的新事件如果失败，会向调用方抛错，但不会自动加入 outbox；调用方可按业务策略重试同一个事件。

可以监控是否发生过容量丢弃：

```dart
if (analytics.droppedPendingEventCount > 0) {
  debugPrint(
    'Dropped ${analytics.droppedPendingEventCount} pending analytics events',
  );
}
```

调试配置来源、缓存和变更：

```dart
final loader = RemoteAnalyticsConfigLoader();
final remoteConfig = RemoteAnalyticsConfig(
  url: Uri.parse(
    'https://config.example.com/event_manager/analytics.remote.json',
  ),
);

final result = await loader.loadResult(remoteConfig);
print(result.source); // remote or cache
print(result.changedFromCache);
print(result.metadata?.sha256);
print(result.previousMetadata?.sha256);

await loader.clearCache(remoteConfig);
```

`changedFromCache` 只在本次远程请求成功，并且远程内容 hash 与已有缓存 hash 不同时为 `true`。

## 上报事件

普通事件：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'view_home',
    parameters: {'source': 'tab'},
  ),
);
```

所有事件调用都应 `await`。Facebook 或 Singular 任一平台调用失败时，SDK 会继续尝试其余 provider，最后抛出带错误明细的 `AnalyticsDeliveryException`：

```dart
try {
  await analytics.track(
    const AnalyticsEvent(name: 'view_home'),
  );
} on AnalyticsDeliveryException catch (error) {
  debugPrint('event=${error.eventName} errors=${error.providerErrors}');
}
```

仓库内补丁版 Singular 的初始化、普通事件、收入事件和用户 ID MethodChannel 调用都返回 `Future<void>`。如果旧业务绕过统一入口直接使用 Singular，也必须 `await Singular.event(...)` 等调用，否则 `PlatformException`、`MissingPluginException` 等错误仍会被业务代码忽略。

收入事件：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'purchase_success',
    parameters: {'product_id': 'sub_monthly'},
    valueToSum: 9.99,
    revenueCurrency: 'USD',
  ),
);
```

收入事件由 `valueToSum` 和 `revenueCurrency` 一起决定。插件会自动把
`revenueCurrency` 转成 Facebook 需要的 `fb_currency` 参数，并在 Singular
侧调用 revenue API；业务代码不需要直接操作第三方 SDK 的货币字段。

`purchase` 和 `purchase_success` 必须同时提供 `valueToSum` 与 `revenueCurrency`，并会在 Facebook 侧调用原生 `logPurchase`。
下列统一事件名会自动转换为 Meta 标准事件名；Singular 仍接收原始统一名称：

- `sign_up`、`view_content`、`rate`、`begin_checkout`
- `add_to_cart`、`add_to_wishlist`、`add_payment_info`
- `subscribe`、`start_trial`、`ad_impression`、`ad_click`
- `tutorial_complete`、`level_achieved`、`unlock_achievement`、`spend_virtual_currency`、`search`

常用事件建议：

- 启动/活跃：`app_open`、`session_start`
- 注册/登录：`sign_up`、`login`
- 内容行为：`view_content`、`search`、`share`、`invite`
- 电商/订阅：`add_to_cart`、`add_to_wishlist`、`begin_checkout`、`add_payment_info`、`purchase_success`、`start_trial`、`subscribe`
- 广告变现：`ad_impression`、`ad_click`
- 游戏/成长：`tutorial_complete`、`level_achieved`、`unlock_achievement`、`spend_virtual_currency`
- 账号资料：`profile_update`、`rate`

用户标识：

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

按事件路由：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'fb_only_event',
    sendToSingular: false,
  ),
);
```

## 平台配置原则

- 生产环境建议在 `Info.plist` / Android resources 中预置 Facebook app id、client token 和两个自动采集开关。
- app id 和 client token 必须与远程 JSON 当前平台分支一致；Android 和 iOS 检测到凭据不一致都会拒绝初始化，避免自动事件和自定义事件进入不同的 Facebook App。
- 自动事件开关允许远程配置覆盖；远程字段省略时保留原生设置。
- 未预置原生值时，SDK 使用兼容的延迟初始化路径。
- Singular api key 和 secret 由远程 JSON 传入。
- iOS 会在远程配置解析成功后、运行时启用 Facebook 自动采集以及启动 Singular 前检查 ATT；状态为 `notDetermined` 时必定请求系统权限。
- 宿主 iOS 工程必须在 `Info.plist` 添加 `NSUserTrackingUsageDescription`。
- 仍需按 Facebook / Singular 官方要求保留宿主工程必要的平台能力配置，例如 install referrer、URL/deep link 能力、混淆规则等。

iOS `Info.plist` 示例：

```xml
<key>FacebookAppID</key>
<string>YOUR_FACEBOOK_APP_ID_IOS</string>
<key>FacebookClientToken</key>
<string>YOUR_FACEBOOK_CLIENT_TOKEN_IOS</string>
<key>FacebookAutoLogAppEventsEnabled</key>
<true/>
<key>FacebookAdvertiserIDCollectionEnabled</key>
<true/>
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads and attribution analytics.</string>
```

Android `res/values/strings.xml`：

```xml
<string name="facebook_app_id">YOUR_FACEBOOK_APP_ID_ANDROID</string>
<string name="facebook_client_token">YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID</string>
```

Android `AndroidManifest.xml` 的 `<application>`：

```xml
<meta-data android:name="com.facebook.sdk.ApplicationId" android:value="@string/facebook_app_id" />
<meta-data android:name="com.facebook.sdk.ClientToken" android:value="@string/facebook_client_token" />
<meta-data android:name="com.facebook.sdk.AutoLogAppEventsEnabled" android:value="true" />
<meta-data android:name="com.facebook.sdk.AdvertiserIDCollectionEnabled" android:value="true" />
```

常规接入建议原生开关与远程 JSON 保持一致。若原生阶段必须禁止采集，可以先在原生配置中设为 `false`，再根据合规策略决定远程配置是继续保持禁用，还是在 ATT 检查完成后显式启用。

## 旧接入方式

旧的 YAML / 原生预填脚本和手动 `init(AnalyticsConfig)` 入口已移除。新接入统一使用远程 JSON 和 `initFromRemoteConfig()`。
