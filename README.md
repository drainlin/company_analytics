# company_analytics

`company_analytics` 是公司 Flutter 应用统一的归因和事件上报入口，目前负责
Facebook App Events 与 Singular 的初始化、事件路由、远程配置和失败队列。

接入时只需要记住三条原则：

| 场景 | 正确做法 |
| --- | --- |
| Facebook 常规事件、购买和订阅 | 由 Meta SDK 自动记录，业务代码不手动打点 |
| Singular 订阅、试用和非订阅内购 | 只调用本包提供的三个固定方法 |
| 特殊自定义事件 | 调用 `trackCustomEvent()`，并显式指定 Facebook、Singular 或两者 |

> Facebook 的自动事件逻辑没有因为手动打点 API 的调整而改变。不要同时向
> Facebook 手动发送购买或订阅事件，否则可能产生重复收入。

## 数据流与职责边界

| 平台 | 数据来源 | 接入要求 |
| --- | --- | --- |
| Facebook | Meta SDK 自动事件 | 宿主接入本包并完成后台配置，业务侧不打常规事件 |
| Singular | SDK 自动会话 + 三个固定手动事件 | 订阅、试用、非订阅内购分别调用对应方法 |
| TikTok | Singular 后台事件映射 | 前端不接入 TikTok SDK |
| Firebase | Firebase SDK 自动事件 | Android 需在 Firebase 后台关联 Google Play |

Singular 可以在后台关联 Facebook，但**不要开启 Revenue Events Postbacks**。
Facebook 已经通过 Meta SDK 自动采集收入，再接收 Singular 的收入回传会造成收入
重复。

## 环境与依赖

- Dart：`>=3.10.0 <4.0.0`
- Flutter：`>=3.38.0`
- `in_app_purchase`：必须精确锁定为 `3.2.4`
- Facebook App Events fork：`0.30.2+company.3`
- Singular Flutter SDK fork：`1.8.0+company.3`
- App Tracking Transparency：`^2.0.7`

暂不支持 Google Play Billing v8。升级 `in_app_purchase` 或间接引入 Billing v8，
可能影响 Meta SDK 自动内购和订阅事件。确认 Meta 兼容前，不要使用
`^3.2.4`、`>=3.2.4` 等宽松约束。

## 安装

内部仓库：

```yaml
dependencies:
  company_analytics:
    git:
      url: http://git.qisoft.cn/dengyulin/company_analytics.git
      ref: v0.2.0

  in_app_purchase: 3.2.4
```

GitHub 仓库：

```yaml
dependencies:
  company_analytics:
    git:
      url: https://github.com/drainlin/company_analytics.git
      ref: v0.2.0

  in_app_purchase: 3.2.4
```

本地开发：

```yaml
dependencies:
  company_analytics:
    path: ../company_analytics

  in_app_purchase: 3.2.4
```

然后执行：

```bash
flutter pub get
```

## 平台与运营后台配置

### Facebook

Facebook 使用 SDK 作为数据源，常规事件、内购和订阅全部依赖自动记录。业务代码
不应再调用 Facebook SDK 手动打这些事件。

iOS 运营配置：

1. 打开 Meta 开发者后台的 **App Settings > Basic**。
2. 在 **Shared secret** 中填写 App Store Connect 的
   **App Information > App-Specific Shared Secret**。
3. 开启 **Log in-app events automatically**。

Android 运营配置：

1. 开启 **Log In-App Purchases Automatically**。
2. 开启 **Log In-App Subscriptions Automatically**。
3. 在订阅自动记录的配置弹窗中，上传 Google Cloud Service Account 的密钥
   JSON 文件。

参考文档：

- [Meta iOS App Events](https://developers.facebook.com/documentation/app-events/getting-started-app-events-ios)
- [Meta iOS App Shared Secret](https://developers.facebook.com/documentation/app-events/getting-started-app-events-ios/app-shared-secret)
- [Meta Android App Events](https://developers.facebook.com/documentation/app-events/getting-started-app-events-android)
- [Meta Android purchase verification](https://developers.facebook.com/documentation/app-events/getting-started-app-events-android/verification)
- [同时使用 Facebook SDK 与 Singular SDK](https://support.singular.net/hc/en-us/articles/360030530092-Using-the-Facebook-SDK-and-Singular-SDK-S2S-in-the-Same-App)

Facebook App ID、Client Token 和自动采集开关由远程 JSON 提供。宿主不需要在
iOS `Info.plist` 或 Android Manifest/resources 中新增 Facebook App ID 和
Client Token，也不需要 Facebook Login、URL Scheme 或 Deep Link 配置。

### iOS ATT

iOS 宿主的 `Info.plist` 必须包含：

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used for attribution analytics.</string>
```

SDK 会在远程配置解析成功后、Facebook 和 Singular 启动前请求 ATT。建议在首屏
渲染后或应用自己的 ATT 说明弹窗后初始化，不要阻塞 Flutter 首帧。

### TikTok

前端不接入 TikTok SDK，在 Singular 后台配置事件映射：

| Singular 官方标准事件 | 实际事件值 | TikTok 事件 |
| --- | --- | --- |
| `EVENT_SNG_SUBSCRIBE` | `sng_subscribe` | `Subscribe` |
| `EVENT_SNG_START_TRIAL` | `sng_start_trial` | `StartTrial` |
| `EVENT_SNG_ECOMMERCE_PURCHASE` | `sng_ecommerce_purchase` | `Purchase` |

### Firebase

Firebase 继续使用其 SDK 自动记录。Android 应在 Firebase 后台
**Project Settings > Integration** 中关联 Google Play。

## 远程配置

iOS 和 Android 共用一个 JSON，通过平台字段保存各自凭据：

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

字段要求：

| 字段 | 规则 |
| --- | --- |
| `version` | 每次修改时递增，用于排查；不参与 SDK 版本比较 |
| `enable_facebook` | 生产环境通常为 `true`；换号时替换凭据，不要关闭自动采集 |
| `enable_singular` | 生产环境通常为 `true` |
| `facebook.ios/android.app_id` | 对应平台有效的 Facebook App ID |
| `facebook.ios/android.client_token` | 必须与对应 App ID 属于同一个 Facebook App |
| `auto_log_app_events_enabled` | 设为 `true`，保持 Facebook 自动事件 |
| `advertiser_tracking_enabled` | 按隐私合规策略显式设置 |
| `singular.enable_logging` | 仅调试时为 `true`，生产环境为 `false` |
| `singular.wait_for_tracking_auth_seconds` | iOS 等待 ATT 的秒数，推荐 `15` |

如果必填值仍为 `YOUR_...` 占位符，SDK 会将对应 provider 视为未配置并跳过。
生产 JSON 不应保留占位符。

本地联调可以编辑
[config/analytics.remote.dev.json](/Users/yulin/Projects/event_manager/config/analytics.remote.dev.json)，
然后执行：

```bash
bash tool/serve_remote_config.sh
```

- iOS Simulator：`http://127.0.0.1:8765/analytics.remote.dev.json`
- Android Emulator：`http://10.0.2.2:8765/analytics.remote.dev.json`

## 初始化

应用进程内只创建一个 `CompanyAnalytics` 实例：

```dart
import 'package:company_analytics/company_analytics.dart';

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
  );
}
```

推荐在 `runApp()` 后调用一次 `initAnalytics()`。SDK 只在初始化时请求远程配置，
不会后台轮询。

Facebook 诊断日志默认在 Debug/Profile 开启、Release 关闭，也可以显式覆盖：

```dart
await analytics.initFromRemoteConfig(
  remoteConfig,
  facebookDebugLoggingEnabled: false,
);
```

开启后会输出配置快照和 Meta 诊断日志，并发送
`company_analytics_diagnostic` 对照事件。原生日志可能包含 Token 或广告标识符，
不要在 Release 开启。

### Facebook 自动事件测试

验证 Facebook 自动内购和订阅事件时，iOS 必须使用 **Profile** 或
**Release** 构建，不要使用 Debug 构建作验收结论：

```bash
flutter run --profile
```

iOS Facebook SDK 18.x 在 Debug 下不允许本包于 CoreKit 初始化前写入远程配置
提供的 App ID 和 Client Token。初始化后再补写虽然可以保留普通手动事件，但
Meta 的服务端配置请求可能已经使用空 App ID，自动 StoreKit 观察器不会可靠启动。
因此 Debug 下没有自动购买事件，不代表 Profile/Release 也存在问题。

验收时应确认：

- Meta 配置请求包含正确 App ID，没有 `apps/(null)`。
- 自动事件包含 `_implicitlyLogged = 1`。
- 内购生成 `fb_mobile_purchase`，订阅生成 `Subscribe`、`StartTrial` 或相应恢复事件。
- `/activities` 最终返回 `200` 和 `success = 1`。

Android 没有这个 iOS Debug 初始化限制；为了使测试构建与正式构建更接近，也建议
使用 Profile 或 Release 验证 Facebook 自动事件。

## 业务打点

### Meta 免费试用纠正

Meta Android 自动内购可能把免费试用识别成付费 `Subscribe`。宿主完成服务端校验后，
对确认属于免费试用的新交易调用固定方法补发正确的 `StartTrial`：

```dart
await analytics.trackFacebookTrialStart(
  subscriptionValue: 13.99,
  currency: 'SGD',
  subscriptionId: 'premium_weekly_trial',
  transactionId: 'transaction_123',
);
```

该方法只发送给 Facebook，不会发送给 Singular 或自定义 provider。SDK 会固定写入
`fb_content_id`、`fb_content_type=subscription`、`fb_order_id`、金额和币种，调用方
传入的 `attributes` 不能覆盖这些关键字段。只在新试用通过业务服务端校验后调用，
恢复购买时不要调用。

### Singular 三个固定方法

正常业务只使用下列三个方法。三个方法都只发送给 Singular，不会调用 Facebook
手动事件 API，也不会转发给注入的自定义 provider。

| 业务场景 | Singular 官方常量 | 实际事件名 | 本包方法 |
| --- | --- | --- | --- |
| 订阅购买成功 | `EVENT_SNG_SUBSCRIBE` | `sng_subscribe` | `trackSingularSubscription()` |
| 免费试用开始 | `EVENT_SNG_START_TRIAL` | `sng_start_trial` | `trackSingularTrialStart()` |
| 非订阅内购成功 | `EVENT_SNG_ECOMMERCE_PURCHASE` | `sng_ecommerce_purchase` | `trackSingularInAppPurchase()` |

这里的 `EVENT_SNG_ECOMMERCE_PURCHASE` 是 Singular 文档中的常量名，SDK 实际
上传的事件值是 `sng_ecommerce_purchase`。

#### 1. 订阅购买成功

```dart
await analytics.trackSingularSubscription(
  amount: 9.99,
  currency: 'USD',
  subscriptionId: 'premium_monthly',
  transactionId: 'transaction_123',
  attributes: const <String, dynamic>{
    'offer_id': 'summer_offer',
  },
);
```

- 只在新订阅购买并完成业务校验后调用。
- restore 不代表新收入，不能调用。
- `amount` 必须是大于 `0` 的有限数。
- `currency` 必须为三位大写 ISO 4217 代码，例如 `USD`、`CNY`。
- `transactionId` 可省略；传入时不能为空。
- 该方法不上传商店 receipt。

#### 2. 免费试用开始

```dart
await analytics.trackSingularTrialStart(
  transactionId: 'transaction_123',
  attributes: const <String, dynamic>{
    'subscription_id': 'premium_monthly',
  },
);
```

试用开始是非收入事件，不传金额和币种。只在新的免费试用真正生效后调用，
恢复历史权益时不要调用。

#### 3. 非订阅内购成功

购买相关类型来自宿主精确锁定的 `in_app_purchase: 3.2.4`：

```dart
import 'package:in_app_purchase/in_app_purchase.dart';

await analytics.trackSingularInAppPurchase(
  purchase: purchaseDetails,
  product: productDetails,
  attributes: const <String, dynamic>{
    'content_type': 'coins',
  },
);
```

方法要求：

- `purchaseDetails.status == PurchaseStatus.purchased`。
- `purchaseDetails.productID == productDetails.id`。
- `productDetails.rawPrice` 必须是大于 `0` 的有限数。
- `productDetails.currencyCode` 是三位大写币种。
- restored、pending、canceled 和 error 状态都不能上报。
- 调用前必须完成 analytics 初始化。

本包只向 Singular 转换并发送商店购买数据，不负责校验用户权益，也不会调用
`InAppPurchase.completePurchase()`。典型接法如下：

```dart
Future<void> handlePurchase(
  PurchaseDetails purchase,
  ProductDetails product,
) async {
  if (purchase.status != PurchaseStatus.purchased) {
    return;
  }

  final bool verified = await verifyPurchaseWithServer(purchase);
  if (!verified) {
    return;
  }

  await analytics.trackSingularInAppPurchase(
    purchase: purchase,
    product: product,
  );

  if (purchase.pendingCompletePurchase) {
    await InAppPurchase.instance.completePurchase(purchase);
  }
}
```

`verifyPurchaseWithServer()` 代表宿主自己的服务端校验。不要因为 analytics 上报
成功就跳过购买校验，也不要由 analytics 包决定是否发放权益。

### 特殊自定义事件

只有无法使用自动事件或上述三个标准事件的特殊需求，才调用
`trackCustomEvent()`。`targets` 是必填且不能为空，不存在默认发送目标。

只发送 Singular：

```dart
await analytics.trackCustomEvent(
  name: 'special_campaign_event',
  parameters: const <String, dynamic>{
    'campaign_id': 'summer_2026',
  },
  targets: const <AnalyticsTarget>{
    AnalyticsTarget.singular,
  },
);
```

确有需要时只发送 Facebook：

```dart
await analytics.trackCustomEvent(
  name: 'special_facebook_event',
  targets: const <AnalyticsTarget>{
    AnalyticsTarget.facebook,
  },
);
```

同时发送两个渠道：

```dart
await analytics.trackCustomEvent(
  name: 'special_shared_event',
  targets: const <AnalyticsTarget>{
    AnalyticsTarget.facebook,
    AnalyticsTarget.singular,
  },
);
```

自定义参数只能使用字符串、数字或布尔值；Map、List 等复杂结构应先转为 JSON
字符串。不要上传密码、Token、身份证号或完整支付信息等敏感数据。

带收入的特殊自定义事件必须同时传金额和币种：

```dart
await analytics.trackCustomEvent(
  name: 'approved_special_revenue',
  valueToSum: 1.99,
  revenueCurrency: 'USD',
  targets: const <AnalyticsTarget>{
    AnalyticsTarget.singular,
  },
);
```

不要用它代替订阅或非订阅内购的固定方法。

### 用户 ID

```dart
await analytics.setUserId('user_123');
await analytics.clearUser();
```

## 队列与错误处理

| 场景 | 行为 |
| --- | --- |
| 初始化前调用订阅、试用或自定义事件 | 写入 `SharedPreferences` outbox，初始化后按顺序补发 |
| 初始化前调用非订阅 IAP | 不缓存收据，抛出 `AnalyticsNotInitializedException` |
| 初始化后事件发送失败 | 抛出 `AnalyticsDeliveryException` |
| outbox 超过容量 | 丢弃最旧事件，并增加 `droppedPendingEventCount` |
| 进程在发送过程中异常退出 | outbox 为 at-least-once 语义，事件可能重复 |

所有 API 调用都应 `await`：

```dart
try {
  await analytics.trackCustomEvent(
    name: 'special_campaign_event',
    targets: const <AnalyticsTarget>{
      AnalyticsTarget.singular,
    },
  );
} on AnalyticsDeliveryException catch (error) {
  debugPrint('event=${error.eventName} errors=${error.providerErrors}');
}
```

默认最多缓存 200 条。可以监控是否发生容量丢弃：

```dart
if (analytics.droppedPendingEventCount > 0) {
  debugPrint(
    'Dropped ${analytics.droppedPendingEventCount} analytics events',
  );
}
```

一个 provider 失败不会阻止 SDK 尝试另一个 provider。

## 配置缓存与 Facebook 换号

初始化时远程配置按以下规则加载：

| 情况 | 行为 |
| --- | --- |
| 远程成功且 JSON 合法 | 使用远程配置并覆盖本地成功缓存 |
| 远程失败但存在缓存 | 使用上一次成功缓存 |
| 远程失败且没有缓存 | 初始化失败；可序列化事件继续进入 outbox |
| 下载成功但 JSON 非法 | 不覆盖已有成功缓存，本次按失败处理 |

查看当前配置来源：

```dart
final result = analytics.lastRemoteConfigResult;
debugPrint('source=${result?.source}');
debugPrint('version=${result?.metadata?.version}');
debugPrint('sha256=${result?.metadata?.sha256}');
debugPrint('changed=${result?.changedFromCache}');
```

Facebook App 失效或换号时不需要重新打包：

1. 准备新的 App ID 和属于同一 App 的 Client Token。
2. 更新远程 JSON 对应平台的凭据。
3. 递增 `version` 并发布 JSON。
4. 确认公开 URL 返回 `200` 和完整合法 JSON。
5. 设备下次冷启动初始化时获取新配置并写入缓存。

SDK 不做进程内定时轮询，也不保证正在运行的进程热切换 Facebook App。换号
边界是：设备重新初始化并成功取得新 JSON 后，当前和后续冷启动使用新凭据。

## 从 0.1.x 迁移到 0.2.0

| 旧用法 | 新用法 |
| --- | --- |
| `track(AnalyticsEvent(...))` 上报订阅 | `trackSingularSubscription()` |
| `track(AnalyticsEvent(...))` 上报试用 | `trackSingularTrialStart()` |
| `track(AnalyticsEvent(...))` 上报非订阅 IAP | `trackSingularInAppPurchase()` |
| 默认向多个 provider 发送自定义事件 | `trackCustomEvent(..., targets: {...})` |

`track(AnalyticsEvent)` 暂时保留以兼容旧代码，但已标记 `@Deprecated`，新业务
不得继续使用。

旧版 YAML、原生预填脚本和手动 `init(AnalyticsConfig)` 入口已经移除。新接入
统一使用远程 JSON 和 `initFromRemoteConfig()`。旧项目残留的 Android
`facebook_config.xml`、Facebook Manifest metadata、iOS
`FacebookConfig.xcconfig`、Info.plist Facebook 字段不会覆盖本包的远程配置，
可以按业务节奏清理。

## 发布前检查

- 远程 JSON URL 返回 `200`，内容合法，`version` 已递增。
- Facebook iOS 已配置 Shared Secret 并开启自动记录内购事件。
- Facebook Android 已开启自动内购和订阅，并上传 Service Account JSON。
- Singular 到 Facebook 的 **Revenue Events Postbacks** 未开启。
- 宿主的 `in_app_purchase` 精确锁定为 `3.2.4`。
- Singular 后台能分别看到 `sng_subscribe`、`sng_start_trial` 和
  `sng_ecommerce_purchase`。
- TikTok 映射分别为 `Subscribe`、`StartTrial`、`Purchase`。
- Facebook 自动内购和订阅已在 Profile 或 Release 构建中验证，未使用 iOS
  Debug 构建作验收结论。
- Release 构建未开启 Facebook 或 Singular 调试日志。
