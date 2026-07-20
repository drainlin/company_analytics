# company_analytics

`company_analytics` 是项目内统一的 Flutter 埋点入口，同时向 Facebook App Events 和 Singular 上报自动事件、自定义事件与收入事件。

本项目只使用 Facebook App Events，不使用 Facebook Login、URL Scheme 或 Deep Link。Facebook app id、client token 和采集开关只以远程 JSON 为准；远程请求失败时使用设备上一次成功缓存的 JSON。

## 快速接入

### 1. 添加依赖

```yaml
dependencies:
  company_analytics:
    git:
      url: http://git.qisoft.cn/dengyulin/company_analytics.git
      ref: v0.1.4
```

执行：

```bash
flutter pub get
```

本地开发可以改为：

```yaml
dependencies:
  company_analytics:
    path: ../company_analytics
```

### 2. 配置 iOS ATT 权限说明

iOS 宿主的 `Info.plist` 必须包含：

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used for attribution analytics.</string>
```

不需要在 iOS `Info.plist` 或 Android Manifest/resources 中配置 Facebook app id 和 client token。旧 SDK 生成的 Facebook 配置可以暂时残留，本 SDK 不会使用它们初始化或路由 App Events。

Android 不需要添加 Facebook 专用的 app id、client token、Login 或 Deep Link 配置。

### 3. 创建远程 JSON

iOS 和 Android 共用一个 JSON，通过平台分支保存各自的凭据：

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
    "enable_logging": false,
    "wait_for_tracking_auth_seconds": 15
  }
}
```

字段规则：

| 字段 | 推荐值或规则 |
| --- | --- |
| `version` | 每次修改配置时递增，便于排查，不参与 SDK 的版本比较 |
| `enable_facebook` | 生产环境保持 `true`；更换 Facebook 账号时不要关闭，只替换凭据 |
| `enable_singular` | 生产环境保持 `true` |
| `facebook.ios/android.app_id` | 对应平台当前有效的 Facebook App ID |
| `facebook.ios/android.client_token` | 必须和对应 App ID 属于同一个 Facebook App |
| `auto_log_app_events_enabled` | 推荐显式填写；需要自动事件时设为 `true` |
| `advertiser_tracking_enabled` | 按隐私合规策略显式填写，不建议依赖默认值 |
| `singular.enable_logging` | 生产环境设为 `false`，仅调试时开启 |
| `singular.wait_for_tracking_auth_seconds` | iOS 等待 ATT 的时间，推荐 `15` |

如果 Facebook 或 Singular 的必填值仍是 `YOUR_...` 占位符，SDK 会把对应 provider 视为未配置并跳过初始化。生产 JSON 不应保留占位符。

配置服务 URL 格式：

```text
https://config.example.com/<app>/<file>.json
```

本地联调可编辑 [analytics.remote.dev.json](/Users/yulin/Projects/event_manager/config/analytics.remote.dev.json)，然后启动：

```bash
bash tool/serve_remote_config.sh
```

- iOS Simulator：`http://127.0.0.1:8765/analytics.remote.dev.json`
- Android Emulator：`http://10.0.2.2:8765/analytics.remote.dev.json`

### 4. 创建单例并初始化

整个应用只创建一个 `CompanyAnalytics` 实例。在首屏渲染后或自定义 ATT 说明弹窗后调用一次初始化：

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

推荐在 `runApp()` 后执行，不要为了等待 ATT 弹窗而阻塞 Flutter 首帧。`facebookTestModeEnabled` 只用于本地调试，生产环境必须为 `false`。

### 5. 上报事件

所有 SDK 调用都必须 `await`：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'view_content',
    parameters: {
      'content_id': 'article_123',
      'source': 'home',
    },
  ),
);
```

设置和清理用户 ID：

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 推荐使用规则

### 配置规则

1. 只以远程 JSON 为配置来源，不要再向原生工程写入 Facebook app id 或 client token。
2. 生产环境保持 Facebook 和 Singular 启用。Facebook 账号失效时替换 app id/client token，不要通过反复关闭 provider 处理。
3. iOS 和 Android 凭据必须分别填写，app id 与 client token 必须成对更新。
4. 每次修改 JSON 都递增 `version`，发布前确认公开 URL 返回 `200` 且内容是完整合法 JSON。
5. 固定配置 URL 和 `cacheKey`，不要在正常升级或换号时主动清理配置缓存。
6. 不要让业务代码直接调用 Facebook 或 Singular SDK，统一通过 `CompanyAnalytics`，否则无法获得统一的错误、路由和队列行为。

### 初始化规则

1. 每个应用进程只初始化一次，不创建多个 `CompanyAnalytics` 实例。
2. SDK 只在调用 `initFromRemoteConfig()` 时请求 JSON，不会在后台轮询配置。
3. 正常事件尽量在初始化完成后发送；初始化前必须发送的事件会进入持久 outbox。
4. iOS ATT 检查发生在配置解析成功后、Facebook 和 Singular 启动前。
5. 初始化失败应记录日志，但通常不需要业务侧立即循环重试；下一次 `track()` 会尝试恢复初始化。

### 事件规则

1. 事件名使用稳定的 `snake_case`，发布后不要随意改名或让同一含义出现多个名称。
2. 参数 key 同样保持稳定；值使用字符串、数字或布尔值。数组、Map 等结构先转成 JSON 字符串。
3. 不上传密码、Token、身份证号、完整支付信息等敏感数据。
4. 每一次 `track()`、`setUserId()` 和 `clearUser()` 都必须 `await`，并按需记录异常。
5. 默认同时发送到 Facebook 和 Singular。只有明确的业务需求才使用 `sendToFacebook` 或 `sendToSingular` 改变路由。
6. 收入事件必须同时传 `valueToSum` 和 ISO 4217 货币代码 `revenueCurrency`。
7. 收入事件建议携带稳定的订单 ID，便于下游对 at-least-once 重试产生的重复事件去重。

## Facebook 配置失效或换号

Facebook 后台账号被封、App 不可用或 client token 失效时，不需要重新打包：

1. 在 Facebook 后台准备新的 App ID 和对应 client token。
2. 同时更新 JSON 中 `facebook.ios` 和 `facebook.android` 的对应凭据。
3. 递增 JSON 的 `version` 并发布。
4. 用浏览器或 `curl` 确认公开 URL 已返回新配置。
5. 设备下一次冷启动调用 `initFromRemoteConfig()` 时会获取并使用新配置；成功配置会写入本地缓存。
6. 后续冷启动如果网络失败，会使用这份已缓存的新配置。

SDK 不做进程内定时轮询，也不要求已经运行的进程热切换 Facebook App。换号后的保证边界是：设备在启动初始化时成功获取新 JSON 后，本次初始化及后续冷启动都会使用新配置；旧 Manifest、resources、Info.plist 或 xcconfig 中的 Facebook 凭据不会覆盖它。

为了实现这一点：

- Android 最终 Manifest 会移除 Meta 的 `FacebookInitProvider`，避免旧原生配置抢先启动 App Events。
- iOS 插件不会在注册时使用 Info.plist 凭据启动 CoreKit，并会把 App Events 绑定到 JSON App ID。
- Android 和 iOS 都不会因为新旧凭据不同而抛出 `CONFIG_MISMATCH`。

## 收入事件

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'purchase_success',
    parameters: {
      'product_id': 'sub_monthly',
      'order_id': 'order_20260720_001',
    },
    valueToSum: 9.99,
    revenueCurrency: 'USD',
  ),
);
```

`purchase` 和 `purchase_success` 必须带收入字段，并在 Facebook 侧使用原生 Purchase API、在 Singular 侧使用 revenue API。业务代码不需要自行添加 `fb_currency`。

## 标准事件映射

以下统一事件名会自动转换为 Meta 标准事件名；Singular 仍接收原始统一名称：

| 业务场景 | 推荐事件名 |
| --- | --- |
| 注册与内容 | `sign_up`、`view_content`、`search`、`rate` |
| 结算与订阅 | `add_to_cart`、`add_to_wishlist`、`begin_checkout`、`add_payment_info`、`purchase_success`、`start_trial`、`subscribe` |
| 广告 | `ad_impression`、`ad_click` |
| 教程与成长 | `tutorial_complete`、`level_achieved`、`unlock_achievement`、`spend_virtual_currency` |

其他自定义名称会按原名称发送。

只发送到一个 provider：

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'facebook_only_event',
    sendToSingular: false,
  ),
);
```

## 缓存、队列与失败行为

### 配置缓存

每次初始化先请求远程 URL：

| 情况 | 行为 |
| --- | --- |
| 远程成功且 JSON 合法 | 使用远程配置，并覆盖本地成功缓存 |
| 远程失败但存在缓存 | 使用上一次成功缓存 |
| 远程失败且没有缓存 | 初始化失败；初始化前事件继续进入 outbox |
| JSON 下载成功但格式或必填字段错误 | 不覆盖已有成功缓存，本次请求按失败处理 |

默认请求最多尝试 3 次、单次超时 15 秒，重试间隔从 500ms 开始退避。

可以检查本次配置来源：

```dart
final result = analytics.lastRemoteConfigResult;
debugPrint('source=${result?.source}');
debugPrint('version=${result?.metadata?.version}');
debugPrint('sha256=${result?.metadata?.sha256}');
debugPrint('changed=${result?.changedFromCache}');
```

### 事件 outbox

- 初始化前事件保存在 `SharedPreferences` 持久 outbox，初始化成功后按顺序补发。
- 默认最多保存 200 条；超限丢弃最旧事件，并增加 `droppedPendingEventCount`。
- 队列采用 at-least-once 语义，进程异常退出时可能重复发送已经成功的事件。
- 已完成初始化后，新的 `track()` 如果发送失败会抛出 `AnalyticsDeliveryException`，不会自动加入 outbox；业务侧可使用同一个事件重试。
- 一个 provider 失败不会阻止 SDK 尝试另一个 provider。

错误处理示例：

```dart
try {
  await analytics.track(
    const AnalyticsEvent(name: 'view_content'),
  );
} on AnalyticsDeliveryException catch (error) {
  debugPrint('event=${error.eventName} errors=${error.providerErrors}');
}
```

监控 outbox 是否发生容量丢弃：

```dart
if (analytics.droppedPendingEventCount > 0) {
  debugPrint(
    'Dropped ${analytics.droppedPendingEventCount} pending analytics events',
  );
}
```

## 版本要求

- Dart：`>=3.8.1 <4.0.0`
- Flutter：`>=3.38.0`
- Facebook App Events fork：`0.30.2+company.2`
- Singular Flutter SDK fork：`1.8.0+company.2`
- App Tracking Transparency：`^2.0.7`

## 旧接入迁移

旧的 YAML、原生预填脚本和手动 `init(AnalyticsConfig)` 入口已经移除。新接入统一使用远程 JSON 和 `initFromRemoteConfig()`。

旧版本残留的这些文件或字段不会影响当前 App Events 配置：

- Android `facebook_config.xml` 和 Facebook Manifest metadata
- iOS `FacebookConfig.xcconfig`、Info.plist Facebook 字段及旧 xcconfig include
- `lib/generated/analytics_env.g.dart`

可以在业务方便时清理，但无需为了 Facebook 换号强制发版删除。
