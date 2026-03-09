# company_analytics

内部统一埋点 SDK（Flutter package），封装：

- `facebook_app_events`
- `singular_flutter_sdk`

目的：让业务同学只接一层 API，减少平台配置和调用方式不一致带来的错误。

## 环境要求

- Dart: `>=3.8.1 <4.0.0`
- Flutter: 以你业务工程版本为准（建议稳定版）

## 提供能力

- 统一 API：`init` / `track` / `setUserId` / `clearUser`
- 初始化幂等：重复调用 `init` 不会重复初始化
- 初始化前事件缓存：默认会排队，初始化后自动补发
- 事件路由控制：可按事件选择发 Facebook / Singular
- 统一异常：`AnalyticsInitializationException`、`AnalyticsNotInitializedException`

## 安装

在业务工程 `pubspec.yaml` 引入：

```yaml
dependencies:
  company_analytics:
    path: ../company_analytics
```

执行：

```bash
flutter pub get
```

## 快速开始

### 1) 全局初始化

建议在 `main()` 启动后尽早初始化：

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:your_app/generated/analytics_env.g.dart';

final analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
  await analytics.init(
    const AnalyticsConfig(
      singularApiKey: AnalyticsEnv.singularApiKey,
      singularSecret: AnalyticsEnv.singularSecret,
      enableFacebook: true,
      enableSingular: true,
      facebookAutoLogAppEventsEnabled: true,
      facebookAdvertiserTrackingEnabled: true,
      singularEnableLogging: false,
      singularWaitForTrackingAuthSeconds: 15,
    ),
  );
}
```

### 2) 上报普通事件

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

### 3) 上报收入事件

当 `valueToSum + revenueCurrency` 同时存在时，会按收入事件处理：

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

### 4) 登录态同步

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 事件路由

默认一个事件同时发 Facebook + Singular。你可以按事件控制：

- 仅 Facebook：`sendToSingular: false`
- 仅 Singular：`sendToFacebook: false`

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'fb_only_event',
    sendToSingular: false,
  ),
);
```

## 初始化前调用策略

默认策略：`track()` 在 `init()` 前被调用时，事件会先缓存，初始化成功后补发。

如需严格模式（初始化前直接抛错）：

```dart
final analytics = CompanyAnalytics(failFastBeforeInit: true);
```

## 团队接入规范（建议强制）

- 业务代码禁止直接 import：
  - `facebook_app_events`
  - `singular_flutter_sdk`
- 事件名统一维护在一个文件（如 `analytics_event_names.dart`）
- `init()` 仅允许在 App 生命周期内调用一次
- 生产环境关闭 `singularEnableLogging`
- 事件参数 key 命名保持稳定，避免频繁改名

## 平台配置清单

这个包只统一 Flutter 调用层，不替代平台原生配置。

### iOS

- Facebook：`Info.plist` 配置 `FacebookAppID`、`FacebookClientToken`、URL Scheme
- Singular：按官方文档完成 iOS 集成与能力配置
- ATT 策略与 `singularWaitForTrackingAuthSeconds` 一致

### Android

- Facebook：`AndroidManifest.xml` 配置 `facebook_app_id`、`facebook_client_token`
- Singular：按官方文档完成 install referrer 与 required metadata
- 混淆场景确认 Proguard / R8 保留规则

## 一键自检（推荐）

为了避免同事漏改原生配置，仓库内提供了检查脚本：

- [check_facebook_setup.sh](/Users/yulin/Projects/event_manager/company_analytics/tool/check_facebook_setup.sh)

在业务工程根目录运行：

```bash
bash ../company_analytics/tool/check_facebook_setup.sh .
```

或者传入业务工程路径：

```bash
bash /Users/yulin/Projects/event_manager/company_analytics/tool/check_facebook_setup.sh /path/to/your_app
```

脚本会检查：

- Android:
  - `android/app/src/main/res/values/facebook_config.xml`（或 `strings.xml`）是否包含 `facebook_app_id` / `facebook_client_token`
  - `android/app/src/main/AndroidManifest.xml` 是否包含 Facebook 的 `meta-data`
- iOS:
  - `ios/Runner/Info.plist` 是否包含 `FacebookAppID` / `FacebookClientToken`
  - 是否存在 `fb<APP_ID>` URL Scheme（`CFBundleURLTypes`）

## 用 YAML 自动生成原生配置（推荐）

你可以把 key 放在 YAML，再用脚本自动生成 Android/iOS 配置。

### 一键命令（推荐）

在宿主工程根目录执行：

```bash
bash ../company_analytics/tool/setup_analytics.sh --app-root .
```

这个命令会自动做三件事：

1. 如果配置文件不存在，自动创建模板：`./config/company_analytics.yaml`
2. 自动模板化原生文件（`AndroidManifest.xml` / `Info.plist`）
3. 根据 YAML 生成 Android/iOS/Dart 配置并自检

说明：

- 原生模板化是“清理并覆盖”模式：
  - 会清理旧的 Facebook `meta-data` / URL Scheme
  - 再写入统一模板，避免历史配置残留

如果第一次运行，会提示你先填写 YAML key，再执行同一条命令即可。

### 手动分步（可选）

#### 1) 在宿主工程创建配置模板

在“业务 Flutter 工程”里执行：

```bash
bash ../company_analytics/tool/sync_analytics_config.sh \
  --app-root . \
  --init-template
```

默认会创建：

- `./config/company_analytics.yaml`

编辑 `config/company_analytics.yaml`：

```yaml
facebook:
  ios:
    app_id: "123456789012345"
    client_token: "YOUR_FACEBOOK_CLIENT_TOKEN_IOS"
    display_name: "Event Manager iOS"
  android:
    app_id: "123456789012345"
    client_token: "YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID"
    display_name: "Event Manager Android"

singular:
  ios:
    api_key: "YOUR_SINGULAR_API_KEY_IOS"
    secret: "YOUR_SINGULAR_SECRET_IOS"
  android:
    api_key: "YOUR_SINGULAR_API_KEY_ANDROID"
    secret: "YOUR_SINGULAR_SECRET_ANDROID"
```

兼容说明：

- 仍兼容旧格式（`facebook.app_id` / `singular.api_key`）
- 若同时存在平台化和旧格式，优先使用平台化字段

### 2) 套用原生模板（一次性）

```bash
bash ../company_analytics/tool/apply_native_templates.sh .
```

### 3) 生成原生配置

```bash
bash ../company_analytics/tool/sync_analytics_config.sh \
  --app-root .
```

如果你想用自定义路径：

```bash
bash ../company_analytics/tool/sync_analytics_config.sh \
  --app-root . \
  --config ./config/company_analytics.prod.yaml
```

会生成/更新：

- Android: `android/app/src/main/res/values/facebook_config.xml`
- iOS: `ios/Flutter/FacebookConfig.xcconfig`
- iOS: 自动确保 `Debug/Release/Profile.xcconfig` 包含 `FacebookConfig.xcconfig`
- Dart: `lib/generated/analytics_env.g.dart`（含平台化常量与向后兼容别名）

### 3) 在 init 中使用 YAML 生成的 Singular Key
### 4) 在 init 中使用 YAML 生成的 Singular Key

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:your_app/generated/analytics_env.g.dart';

Future<void> initAnalytics(CompanyAnalytics analytics) async {
  await analytics.init(
    const AnalyticsConfig(
      singularApiKey: AnalyticsEnv.singularIosApiKey,
      singularSecret: AnalyticsEnv.singularIosSecret,
      enableFacebook: true,
      enableSingular: true,
      facebookAutoLogAppEventsEnabled: true,
      facebookAdvertiserTrackingEnabled: true,
      singularEnableLogging: false,
      singularWaitForTrackingAuthSeconds: 15,
    ),
  );
}
```

### 5) 运行自检

```bash
bash ../company_analytics/tool/check_facebook_setup.sh .
```

### 6) 一次性确认 Info.plist 使用变量

`Info.plist` 需要改成变量引用（只需做一次）：

- `FacebookAppID` -> `$(FACEBOOK_APP_ID)`
- `FacebookClientToken` -> `$(FACEBOOK_CLIENT_TOKEN)`
- URL Scheme -> `fb$(FACEBOOK_APP_ID)`

## 常见问题

### 1. 初始化失败

症状：抛出 `AnalyticsInitializationException`。

排查顺序：

1. 检查 `singularIosApiKey` / `singularIosSecret`（或你实际使用的平台字段）是否为空
2. 检查 iOS/Android 平台配置是否完整
3. 检查是否把两个 provider 都关闭了（`enableFacebook=false` 且 `enableSingular=false`）

### 2. 事件没有上报

排查顺序：

1. 确认 `init()` 已执行成功
2. 确认事件没有被路由开关关闭（`sendToFacebook` / `sendToSingular`）
3. 在测试环境打开 `singularEnableLogging` 查看日志

### 3. 初始化前埋点行为不符合预期

- 默认是缓存后补发
- 需要严格失败时使用 `CompanyAnalytics(failFastBeforeInit: true)`

## 对外 API

当前 `package:company_analytics/company_analytics.dart` 导出以下接口：

### 1) `CompanyAnalytics`

统一埋点入口。

构造：

- `CompanyAnalytics({List<AnalyticsProvider>? providers, bool failFastBeforeInit = false})`

字段：

- `bool get isInitialized`

方法：

- `Future<void> init(AnalyticsConfig config)`
- `Future<void> track(AnalyticsEvent event)`
- `Future<void> setUserId(String userId)`
- `Future<void> clearUser()`

### 2) `AnalyticsConfig`

初始化配置模型。

构造参数（核心）：

- `singularApiKey`
- `singularSecret`
- `enableFacebook`
- `enableSingular`
- `queueEventsBeforeInit`
- `failFastOnTrackBeforeInit`
- `facebookAutoLogAppEventsEnabled`
- `facebookAdvertiserTrackingEnabled`
- `singularEnableLogging`
- `singularWaitForTrackingAuthSeconds`

方法：

- `List<String> validate({bool hasCustomProviders = false})`

### 3) `AnalyticsEvent`

事件模型。

构造参数：

- `name`
- `parameters`
- `valueToSum`
- `revenueCurrency`
- `sendToFacebook`
- `sendToSingular`

字段/方法：

- `bool get hasRevenue`
- `AnalyticsEvent copyWith(...)`

### 4) 异常类型

- `AnalyticsInitializationException`
- `AnalyticsNotInitializedException`

### 5) `AnalyticsSdkSingletons`（原始 SDK 单例访问）

仅在必须使用底层 SDK 时使用。

- `AnalyticsSdkSingletons.facebookAppEvents`（`@Deprecated`）
- `AnalyticsSdkSingletons.singular`（`@Deprecated`）

### 6) `SingularSdkFacade`

`AnalyticsSdkSingletons.singular` 返回的 facade 类型，公开方法：

- `start(SingularConfig config)`
- `event(String eventName)`
- `eventWithArgs(String eventName, Map args)`
- `customRevenueWithAttributes(String eventName, String currency, double amount, Map attributes)`
- `setCustomUserId(String customUserId)`
- `unsetCustomUserId()`

### 7) 测试辅助（不建议业务使用）

- `InMemoryAnalyticsProvider`（`@visibleForTesting`）

## 暴露原始 SDK 单例（带警告）

如果你必须直接调用原始 SDK（例如做某个非常规能力），可以使用：

```dart
import 'package:company_analytics/company_analytics.dart';

final fb = AnalyticsSdkSingletons.facebookAppEvents; // IDE 会显示 Deprecated 警告
final singular = AnalyticsSdkSingletons.singular; // IDE 会显示 Deprecated 警告
```

默认行为：

- 两个 getter 带 `@Deprecated` 标记，使用处会在 IDE/Analyzer 里标黄
- 目的是提醒同学：直接调用会绕过统一埋点规范

## 版本建议

建议将事件定义（名称 + 参数）版本化管理，发布时在变更说明中标注新增/删除/重命名事件，避免数据口径漂移。
