# Singular iOS 购买事件测试

这个 example 只创建 iOS 工程，用真实的 App Store Sandbox 交易验证：

| 产品 ID | 类型 | Singular 事件 |
| --- | --- | --- |
| `test.1000` | 非订阅内购 | `sng_ecommerce_purchase` |
| `test.year` | 自动续期订阅 | `sng_subscribe` |
| `test.more1` | 自动续期订阅 | `sng_subscribe` |

## 运行前准备

1. 确认远程 JSON 中启用了 Singular，并包含有效的 iOS API Key 和 Secret。
   example 默认使用：
   `https://analytics-config-worker.yyy713321.workers.dev/test_only/analytics.remote.json`
   App 会在初始化前检查 `enable_singular`，为 `false` 时直接提示且不允许购买，
   避免把未实际发送的事件误判为成功。
2. Runner 的 Bundle Identifier 已设为 `test.com.ai.virl`，需要和 App Store Connect
   中拥有上述三个产品的 App 一致。
3. 确认 Paid Applications 协议有效、产品已可用于 Sandbox 测试。
4. 建议使用真机和 Sandbox Apple Account。Xcode 本地 StoreKit Configuration
   可以测试 UI，但本地 receipt 不适合拿来判断 Singular 服务端收入验证是否成功。

运行：

```bash
cd example
flutter pub get
flutter run
```

进入应用后点击“初始化并加载商品”，三个商品都显示商店价格后再购买。

初始化前可以选择 **StoreKit 1** 或 **StoreKit 2**。选择会在
`InAppPurchase.instance` 首次创建前生效；购买监听注册后本次进程会锁定版本，
需要重启 App 才能切换。StoreKit 2 要求 iOS 15 或更高版本。运行日志会显示
`AppStorePurchaseDetails` 或 `SK2PurchaseDetails`，事件参数也会附带
`storekit_version=storekit_1/storekit_2`，便于在 Singular 中区分。

## 上报规则

- `test.1000` 新购成功：把 `PurchaseDetails` 和 `ProductDetails` 交给
  `trackSingularInAppPurchase()`，成功后才结束 StoreKit 交易。
- StoreKit 1 会先检查 App Receipt；为空时执行 `SKReceiptRefreshRequest`，刷新后仍为空
  则保留未完成交易，不向 Singular 提交无效收入。日志只输出 receipt 长度，不输出内容。
- StoreKit 1 随后通过原生 `SKPaymentQueue` 匹配 transaction ID，并调用 Singular
  `iapComplete:withName:`。远程配置开启 `singular.enable_logging` 后，可搜索
  `[company_analytics][Singular]`、`[SingularFlutter][Dart]`、
  `[SingularFlutter][iOS]` 和 Singular SDK 自身的 Verbose 日志。
- 两个订阅新购成功：使用商店返回的实际价格、币种和 transaction ID 调用
  `trackSingularSubscription()`。
- restored 交易只恢复权益，不发送 Singular 新收入事件。
- example 为方便 Sandbox 测试，没有业务服务端验单。生产应用必须在上报和发放权益前
  完成服务端验证，并对 transaction ID 做持久化去重。
