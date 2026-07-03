# company_analytics 开发文档

这个包是项目内统一埋点入口，封装仓库内置的 Facebook App Events 和 Singular Flutter SDK。

当前主流程是运行时远程配置：启动时从 URL 拉取 JSON，按平台解析参数，再由 Flutter 传给 Facebook / Singular 初始化。开发期不再把 Facebook app id、client token 或 Singular key 预先写入业务工程。

## 环境要求

- Dart: `>=3.8.1 <4.0.0`
- Flutter: `>=3.38.0`
- Facebook App Events Flutter SDK: 仓库内置版本 `0.30.2`
- Singular Flutter SDK: 仓库内补丁版本 `1.8.0+company.1`
  - Android Singular SDK: `12.14.0`
  - iOS Singular SDK: `12.12.0`

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

业务侧推荐只调用 `initFromRemoteConfig()`：

```dart
import 'package:company_analytics/company_analytics.dart';

final analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
  await analytics.initFromRemoteConfig(
    RemoteAnalyticsConfig(
      url: Uri.parse(
        'https://config.example.com/event_manager/analytics.remote.json',
      ),
      timeout: const Duration(seconds: 3),
      useCachedConfigOnFailure: true,
    ),
  );
}
```

初始化顺序：

1. `RemoteAnalyticsConfigLoader` 请求 URL。
2. 按当前平台解析 JSON。
3. 校验 `AnalyticsConfig`。
4. Facebook provider 调用 `FacebookAppEvents.configure(appId, clientToken)`。
5. Facebook native SDK 在收到 runtime 参数后初始化。
6. Singular provider 使用 runtime key/secret 初始化。
7. 初始化前缓存的事件开始补发。

远程请求默认最多尝试 3 次：

```dart
RemoteAnalyticsConfig(
  url: Uri.parse(
    'https://config.example.com/event_manager/analytics.remote.json',
  ),
  timeout: const Duration(seconds: 3),
  maxAttempts: 3,
  retryDelay: const Duration(milliseconds: 500),
  retryBackoffMultiplier: 2,
  useCachedConfigOnFailure: true,
)
```

如果所有远程请求都失败，会再尝试读取上一次成功缓存。没有缓存时才抛出 `AnalyticsInitializationException`。

如果启动阶段初始化失败，`CompanyAnalytics` 会保留最近一次 `RemoteAnalyticsConfig` 和 loader。后续 `track()` 发现还没有成功初始化时，会先立即重试远程初始化；重试成功后上报当前事件，重试失败则按原策略把事件排队，或在 fail-fast 模式下抛 `AnalyticsNotInitializedException`。

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

不要再把以下值写入业务工程的 `Info.plist`、`AndroidManifest.xml` 或 Android resources：

- Facebook app id
- Facebook client token
- Singular api key
- Singular secret

仍需保留 SDK 正常运行需要的平台能力配置，例如：

- iOS ATT 权限说明和授权流程
- iOS/Android deep link 或 URL scheme 能力，如果业务场景需要
- Android install referrer
- Android Proguard / R8 保留规则

## 事件上报

普通事件：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'event_page_view',
    parameters: {
      'page': 'event_detail',
      'source': 'push',
    },
  ),
);
```

收入事件：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'purchase_success',
    parameters: {
      'sku': 'vip_monthly',
      'channel': 'paywall_a',
    },
    valueToSum: 9.99,
    revenueCurrency: 'USD',
  ),
);
```

事件路由：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'fb_only_event',
    sendToSingular: false,
  ),
);
```

登录态：

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 初始化前事件策略

默认策略：`track()` 在 `init()` 前被调用时，事件会先缓存，初始化成功后补发。

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
2. 确认事件没有被 `sendToFacebook` / `sendToSingular` 路由关闭。
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
- `AnalyticsConfig`
- `AnalyticsEvent`
- `AnalyticsProvider`
- `RemoteAnalyticsConfig`
- `RemoteAnalyticsConfigLoader`
- `RemoteAnalyticsConfigResult`
- `RemoteAnalyticsConfigMetadata`
- `RemoteAnalyticsConfigSource`
- `AnalyticsInitializationException`
- `AnalyticsNotInitializedException`
- `InMemoryAnalyticsProvider`

`AnalyticsSdkSingletons.facebookAppEvents` 和 `AnalyticsSdkSingletons.singular` 仍保留，但已标记 `@Deprecated`。业务代码应优先走 `CompanyAnalytics`。

## Legacy 脚本

旧 YAML / 原生预填脚本已移动到 `tool/legacy/`，只用于历史项目迁移或排查旧接入方式。新接入不需要执行这些命令。

CLI 仍保留兼容入口：

```bash
dart run company_analytics:company_analytics setup --app-root .
dart run company_analytics:company_analytics sync --app-root .
dart run company_analytics:company_analytics apply .
dart run company_analytics:company_analytics check .
```

这些命令会操作旧的 YAML/native 预填流程，不属于当前推荐接入路径。

## 开发校验

修改插件后至少运行：

```bash
flutter analyze
flutter test
```
