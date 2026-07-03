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

## 安装

Git 依赖：

```yaml
dependencies:
  company_analytics:
    git:
      url: http://git.qisoft.cn/dengyulin/company_analytics.git
      ref: v0.0.6
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

开发期可以先编辑仓库内的本地 JSON：

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

每次启动会先请求远程 URL；成功解析后写入本地缓存。网络失败时会使用上一次成功解析的缓存。缓存 metadata 包含 `version`、`sha256`、`source_url`、`cached_at`。

## 初始化

建议在 `main()` 启动早期初始化：

```dart
import 'package:company_analytics/company_analytics.dart';

final CompanyAnalytics analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
  await analytics.initFromRemoteConfig(
    RemoteAnalyticsConfig(
      url: Uri.parse(
        'http://127.0.0.1:8765/analytics.remote.dev.json',
      ),
    ),
  );
}
```

调试配置来源、缓存和变更：

```dart
final loader = RemoteAnalyticsConfigLoader();
final remoteConfig = RemoteAnalyticsConfig(
  url: Uri.parse('http://127.0.0.1:8765/analytics.remote.dev.json'),
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
- 仍需按 Facebook / Singular 官方要求保留宿主工程必要的平台能力配置，例如 ATT、install referrer、URL/deep link 能力、混淆规则等。

## Legacy 工具

旧的 YAML / 原生预填脚本已移动到 `tool/legacy/`，只用于历史项目迁移或排查旧接入方式：

```bash
dart run company_analytics:company_analytics setup --app-root .
dart run company_analytics:company_analytics sync --app-root .
dart run company_analytics:company_analytics apply .
dart run company_analytics:company_analytics check .
```

新接入不需要运行这些命令。
