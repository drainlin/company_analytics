# company_analytics

`company_analytics` 是项目内统一埋点入口，封装仓库内置的 Facebook App Events 和 Singular Flutter SDK。

当前推荐方案：启动时从 URL 拉取统一 JSON，按平台解析 Facebook / Singular 参数，再由 Flutter 运行时传给 SDK。不要再把 Facebook app id、client token 或 Singular key 预先写入业务工程。

## 版本要求

- Dart: `>=3.8.1 <4.0.0`
- Flutter: `>=3.38.0`
- Facebook App Events Flutter SDK: 仓库内置版本 `0.30.2`
- Singular Flutter SDK: 仓库内补丁版本 `1.8.0+company.1`
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
      ref: v0.1.0
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

每次启动会先请求远程 URL；成功解析后写入本地缓存。网络失败时会使用上一次成功解析的缓存。缓存 metadata 包含 `version`、`sha256`、`source_url`、`cached_at`。

远程请求默认最多尝试 3 次，每次请求默认超时 3 秒，重试间隔从 500ms 开始退避。如果所有远程请求都失败，再按 `useCachedConfigOnFailure` 决定是否使用缓存。

## 初始化

建议在首屏渲染后或业务自定义 ATT 说明弹窗后初始化。iOS 会在 `initFromRemoteConfig()` 内部请求 ATT，因此不要在 `runApp()` 之前 `await` 这个初始化；SDK 仍会等到 ATT 检查完成后才启动。

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:flutter/foundation.dart';

final CompanyAnalytics analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
  await analytics.initFromRemoteConfig(
    RemoteAnalyticsConfig(
      url: Uri.parse(
        'https://config.example.com/event_manager/analytics.remote.json',
      ),
      timeout: const Duration(seconds: 3),
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

- Facebook app id 和 client token 由远程 JSON 传入，不再依赖 `Info.plist` 或 Android resources。
- Facebook SDK 已改为延迟初始化：Flutter 传入 app id 和 client token 后才会启动。
- Singular api key 和 secret 由远程 JSON 传入。
- iOS 会在远程配置解析成功后、Facebook / Singular native SDK 初始化前检查 ATT；状态为 `notDetermined` 时必定请求系统权限。
- 宿主 iOS 工程必须在 `Info.plist` 添加 `NSUserTrackingUsageDescription`。
- 仍需按 Facebook / Singular 官方要求保留宿主工程必要的平台能力配置，例如 install referrer、URL/deep link 能力、混淆规则等。

iOS `Info.plist` 示例：

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads and attribution analytics.</string>
```

## 旧接入方式

旧的 YAML / 原生预填脚本和手动 `init(AnalyticsConfig)` 入口已移除。新接入统一使用远程 JSON 和 `initFromRemoteConfig()`。
