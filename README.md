# company_analytics

## 1. 安装

### 方式 A：Git 依赖（推荐）

```yaml
dependencies:
  company_analytics:
    git:
      url: http://git.qisoft.cn/dengyulin/company_analytics.git
```

### 方式 B：本地 path 依赖

```yaml
dependencies:
  company_analytics:
    path: ../company_analytics
```

然后执行：

```bash
flutter pub get
```

## 2. 配置 YAML

在宿主工程准备配置文件：`config/company_analytics.yaml`

```yaml
facebook:
  ios:
    app_id: "YOUR_FACEBOOK_APP_ID_IOS"
    client_token: "YOUR_FACEBOOK_CLIENT_TOKEN_IOS"
    display_name: "Your App iOS"
  android:
    app_id: "YOUR_FACEBOOK_APP_ID_ANDROID"
    client_token: "YOUR_FACEBOOK_CLIENT_TOKEN_ANDROID"
    display_name: "Your App Android"

singular:
  ios:
    api_key: "YOUR_SINGULAR_API_KEY_IOS"
    secret: "YOUR_SINGULAR_SECRET_IOS"
  android:
    api_key: "YOUR_SINGULAR_API_KEY_ANDROID"
    secret: "YOUR_SINGULAR_SECRET_ANDROID"
```

兼容说明：仍兼容旧格式（`facebook.app_id` / `singular.api_key`）；若同时存在，优先平台化字段。

## 3. 一键同步原生配置

在宿主工程根目录执行：

```bash
bash ../company_analytics/tool/setup_analytics.sh --app-root .
```

该命令会自动完成：

1. 套用原生模板（Android Manifest + iOS Info.plist）
2. 从 YAML 生成原生配置
3. 生成 Dart 常量文件 `lib/generated/analytics_env.g.dart`
4. 运行 Facebook 原生配置检查脚本

iOS 会自动写入：

- `FacebookAdvertiserIDCollectionEnabled = true`
- `FacebookAutoLogAppEventsEnabled = true`

## 4. Flutter 初始化

建议在 `main()` 启动早期初始化：

```dart
import 'package:company_analytics/company_analytics.dart';
import 'package:your_app/generated/analytics_env.g.dart';

final CompanyAnalytics analytics = CompanyAnalytics();

Future<void> initAnalytics() async {
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

## 5. 上报事件

### 普通事件

```dart
await analytics.track(
  const AnalyticsEvent(
    name: 'view_home',
    parameters: {'source': 'tab'},
  ),
);
```

### 收入事件

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

### 登录态同步

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 6. 自检

```bash
bash ../company_analytics/tool/check_facebook_setup.sh .
```

通过标准：`Result: PASSED (0 failures, 0 warnings)`。
