import 'dart:async';

import 'package:company_analytics/company_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

const String purchaseProductId = 'test.1000';
const String yearlySubscriptionId = 'test.year';
const String moreSubscriptionId = 'test.more1';

const List<String> productIds = <String>[
  purchaseProductId,
  yearlySubscriptionId,
  moreSubscriptionId,
];

const String defaultRemoteConfigUrl =
    'https://analytics-config-worker.yyy713321.workers.dev/'
    'test_only/analytics.remote.json';

enum StoreKitVersion {
  storeKit1('StoreKit 1'),
  storeKit2('StoreKit 2');

  const StoreKitVersion(this.label);

  final String label;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SingularPurchaseExampleApp());
}

class SingularPurchaseExampleApp extends StatelessWidget {
  const SingularPurchaseExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Singular iOS 购买测试',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3457d5)),
        useMaterial3: true,
      ),
      home: const SingularPurchasePage(),
    );
  }
}

class SingularPurchasePage extends StatefulWidget {
  const SingularPurchasePage({super.key});

  @override
  State<SingularPurchasePage> createState() => _SingularPurchasePageState();
}

class _SingularPurchasePageState extends State<SingularPurchasePage> {
  final CompanyAnalytics _analytics = CompanyAnalytics();
  final TextEditingController _configUrlController = TextEditingController(
    text: defaultRemoteConfigUrl,
  );
  final Map<String, ProductDetails> _products = <String, ProductDetails>{};
  final Map<String, PurchaseDetails> _pendingReports =
      <String, PurchaseDetails>{};
  final List<String> _logs = <String>[];
  final Set<String> _reportingTransactions = <String>{};
  final Set<String> _reportedTransactions = <String>{};

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  InAppPurchase? _store;
  StoreKitVersion _selectedStoreKitVersion = StoreKitVersion.storeKit2;
  StoreKitVersion? _activeStoreKitVersion;
  bool _analyticsReady = false;
  bool _storeAvailable = false;
  bool _initializing = false;
  bool _loadingProducts = false;
  String? _buyingProductId;

  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void dispose() {
    final purchaseSubscription = _purchaseSubscription;
    if (purchaseSubscription != null) {
      unawaited(purchaseSubscription.cancel());
    }
    _configUrlController.dispose();
    super.dispose();
  }

  Future<void> _initializeAndLoadProducts() async {
    if (_initializing) {
      return;
    }

    final uri = Uri.tryParse(_configUrlController.text.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      _addLog('请输入有效的远程 JSON 地址。');
      return;
    }

    setState(() => _initializing = true);
    try {
      _addLog('开始初始化 CompanyAnalytics…');
      final remoteConfig = RemoteAnalyticsConfig(
        url: uri,
        maxAttempts: 1,
        useCachedConfigOnFailure: false,
      );
      final configResult = await RemoteAnalyticsConfigLoader().loadResult(
        remoteConfig,
      );
      if (!configResult.config.enableSingular) {
        throw StateError('远程 JSON 的 enable_singular=false；请改为 true 后重试。');
      }
      await _configureStoreKitIfNeeded();
      await _analytics.initFromRemoteConfig(
        remoteConfig,
        loader: _PreloadedRemoteConfigLoader(configResult),
        facebookDebugLoggingEnabled: false,
      );
      if (!mounted) {
        return;
      }
      setState(() => _analyticsReady = true);
      _addLog('Singular 初始化完成。');
      await _loadProducts();
    } catch (error) {
      _addLog('初始化失败：$error');
    } finally {
      if (mounted) {
        setState(() => _initializing = false);
      }
    }
  }

  Future<void> _configureStoreKitIfNeeded() async {
    if (_store != null) {
      return;
    }

    final supportsStoreKit2 = await SKRequestMaker.supportsStoreKit2();
    switch (_selectedStoreKitVersion) {
      case StoreKitVersion.storeKit1:
        // StoreKit 1 is deprecated, but this option intentionally exercises it.
        // ignore: deprecated_member_use
        await InAppPurchaseStoreKitPlatform.enableStoreKit1();
        break;
      case StoreKitVersion.storeKit2:
        if (!supportsStoreKit2) {
          throw UnsupportedError('StoreKit 2 需要 iOS 15 或更高版本。');
        }
        // ignore: deprecated_member_use
        await InAppPurchaseStoreKitPlatform.enableStoreKit2();
        break;
    }

    final actualVersion = InAppPurchaseStoreKitPlatform.isStoreKit2Enabled
        ? StoreKitVersion.storeKit2
        : StoreKitVersion.storeKit1;
    if (actualVersion != _selectedStoreKitVersion) {
      throw StateError(
        '请求 ${_selectedStoreKitVersion.label}，插件实际选择了 ${actualVersion.label}。',
      );
    }

    final store = InAppPurchase.instance;
    _purchaseSubscription = store.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        _addLog('购买流错误：$error');
      },
    );
    if (!mounted) {
      await _purchaseSubscription?.cancel();
      return;
    }
    setState(() {
      _store = store;
      _activeStoreKitVersion = actualVersion;
    });
    _addLog('已启用 ${actualVersion.label}，本次进程内不可切换。');
  }

  Future<void> _loadProducts() async {
    final store = _store;
    if (!_isIOS || _loadingProducts || store == null) {
      if (_isIOS && store == null) {
        _addLog('请先选择 StoreKit 版本并完成初始化。');
      }
      return;
    }

    setState(() => _loadingProducts = true);
    try {
      final available = await store.isAvailable();
      if (!mounted) {
        return;
      }
      setState(() => _storeAvailable = available);
      if (!available) {
        _addLog('App Store 当前不可用，请检查设备网络和 Sandbox 账号。');
        return;
      }

      final response = await store.queryProductDetails(productIds.toSet());
      if (response.error != null) {
        _addLog('商品查询错误：${response.error}');
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _products
          ..clear()
          ..addEntries(
            response.productDetails.map(
              (product) =>
                  MapEntry<String, ProductDetails>(product.id, product),
            ),
          );
      });
      _addLog(
        '已加载 ${response.productDetails.length}/${productIds.length} 个商品。',
      );
      if (response.notFoundIDs.isNotEmpty) {
        _addLog('未找到：${response.notFoundIDs.join(', ')}');
      }
      await _retryPendingReports();
    } catch (error) {
      _addLog('加载商品失败：$error');
    } finally {
      if (mounted) {
        setState(() => _loadingProducts = false);
      }
    }
  }

  Future<void> _buy(String productId) async {
    final store = _store;
    final product = _products[productId];
    if (store == null ||
        !_analyticsReady ||
        !_storeAvailable ||
        product == null) {
      _addLog('请先成功初始化并加载 $productId。');
      return;
    }

    setState(() => _buyingProductId = productId);
    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      final accepted = productId == purchaseProductId
          ? await store.buyConsumable(purchaseParam: purchaseParam)
          : await store.buyNonConsumable(purchaseParam: purchaseParam);
      _addLog(accepted ? '已提交 $productId 购买请求。' : '$productId 购买请求未提交。');
    } catch (error) {
      _addLog('发起 $productId 购买失败：$error');
    } finally {
      if (mounted) {
        setState(() => _buyingProductId = null);
      }
    }
  }

  void _onPurchaseUpdates(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      unawaited(_handlePurchase(purchase));
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    _addLog(
      '${purchase.productID} 状态：${purchase.status.name} '
      '(${purchase.runtimeType})',
    );

    switch (purchase.status) {
      case PurchaseStatus.pending:
        return;
      case PurchaseStatus.purchased:
        await _reportNewPurchase(purchase);
        return;
      case PurchaseStatus.restored:
        _addLog('${purchase.productID} 是恢复交易，不向 Singular 上报新收入。');
        await _completeIfNeeded(purchase);
        return;
      case PurchaseStatus.error:
        _addLog('${purchase.productID} 购买错误：${purchase.error}');
        await _completeIfNeeded(purchase);
        return;
      case PurchaseStatus.canceled:
        _addLog('${purchase.productID} 已取消。');
        await _completeIfNeeded(purchase);
        return;
    }
  }

  Future<void> _reportNewPurchase(PurchaseDetails purchase) async {
    final transactionKey = _transactionKey(purchase);
    final product = _products[purchase.productID];
    if (!_analyticsReady || product == null) {
      _pendingReports[transactionKey] = purchase;
      _addLog('尚未准备好上报 ${purchase.productID}，已保留交易等待初始化。');
      return;
    }

    if (_reportedTransactions.contains(transactionKey)) {
      _addLog('已忽略当前进程内的重复交易：$transactionKey');
      await _completeIfNeeded(purchase);
      return;
    }
    if (!_reportingTransactions.add(transactionKey)) {
      return;
    }

    try {
      // 这里只为跑通 Sandbox 链路而视为校验成功。生产应用必须替换为服务端验单。
      _addLog('[Sandbox] 假定服务端已验证交易 $transactionKey。');
      final eventAttributes = <String, dynamic>{
        'example_mode': 'ios_sandbox',
        'storekit_version': switch (_activeStoreKitVersion) {
          StoreKitVersion.storeKit1 => 'storekit_1',
          StoreKitVersion.storeKit2 => 'storekit_2',
          null => 'unknown',
        },
      };
      if (purchase.productID == purchaseProductId) {
        final purchaseForSingular = await _preparePurchaseForSingular(purchase);
        await _analytics.trackSingularInAppPurchase(
          purchase: purchaseForSingular,
          product: product,
          attributes: eventAttributes,
        );
        _addLog(
          '已提交 Singular SDK sng_ecommerce_purchase：${purchase.productID}',
        );
      } else if (purchase.productID == yearlySubscriptionId ||
          purchase.productID == moreSubscriptionId) {
        await _analytics.trackSingularSubscription(
          amount: product.rawPrice,
          currency: product.currencyCode.toUpperCase(),
          subscriptionId: purchase.productID,
          transactionId: purchase.purchaseID,
          attributes: eventAttributes,
        );
        _addLog('已发送 Singular sng_subscribe：${purchase.productID}');
      } else {
        _addLog('未知商品 ${purchase.productID}，未上报。');
        return;
      }

      _reportedTransactions.add(transactionKey);
      _pendingReports.remove(transactionKey);
      await _completeIfNeeded(purchase);
    } catch (error) {
      _addLog('Singular 上报失败，交易保留以便重试：$error');
    } finally {
      _reportingTransactions.remove(transactionKey);
    }
  }

  Future<PurchaseDetails> _preparePurchaseForSingular(
    PurchaseDetails purchase,
  ) async {
    var receipt = purchase.verificationData.serverVerificationData;
    _addLog(
      '${_activeStoreKitVersion?.label ?? 'StoreKit'} '
      'transaction=${purchase.purchaseID ?? 'null'} '
      'receiptLength=${receipt.length}',
    );

    if (_activeStoreKitVersion != StoreKitVersion.storeKit1) {
      if (receipt.isEmpty) {
        throw StateError('StoreKit 2 transaction JWS 为空，无法上报 Singular。');
      }
      return purchase;
    }

    if (purchase is! AppStorePurchaseDetails) {
      throw StateError('选择了 StoreKit 1，但收到的类型是 ${purchase.runtimeType}。');
    }

    if (receipt.isEmpty) {
      _addLog('StoreKit 1 App Receipt 为空，开始执行 SKReceiptRefreshRequest…');
      await SKRequestMaker().startRefreshReceiptRequest();
      receipt = await SKReceiptManager.retrieveReceiptData();
      _addLog('StoreKit 1 Receipt 刷新完成，receiptLength=${receipt.length}');
    }

    if (receipt.isEmpty) {
      throw StateError('StoreKit 1 App Receipt 刷新后仍为空，暂不结束交易。');
    }
    if (purchase.purchaseID?.trim().isEmpty ?? true) {
      throw StateError('StoreKit 1 transaction ID 为空，暂不结束交易。');
    }
    if (receipt == purchase.verificationData.serverVerificationData) {
      return purchase;
    }

    return AppStorePurchaseDetails(
      purchaseID: purchase.purchaseID,
      productID: purchase.productID,
      verificationData: PurchaseVerificationData(
        localVerificationData: receipt,
        serverVerificationData: receipt,
        source: purchase.verificationData.source,
      ),
      transactionDate: purchase.transactionDate,
      skPaymentTransaction: purchase.skPaymentTransaction,
      status: purchase.status,
    );
  }

  Future<void> _retryPendingReports() async {
    if (_pendingReports.isEmpty) {
      return;
    }
    _addLog('开始重试 ${_pendingReports.length} 笔启动时收到的未完成交易。');
    for (final purchase in _pendingReports.values.toList(growable: false)) {
      await _reportNewPurchase(purchase);
    }
  }

  String _transactionKey(PurchaseDetails purchase) {
    return purchase.purchaseID ??
        '${purchase.productID}:${purchase.transactionDate ?? 'unknown'}';
  }

  Future<void> _completeIfNeeded(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) {
      return;
    }
    try {
      final store = _store;
      if (store == null) {
        throw StateError('StoreKit 尚未初始化。');
      }
      await store.completePurchase(purchase);
      _addLog('已完成 StoreKit 交易：${purchase.purchaseID ?? purchase.productID}');
    } catch (error) {
      _addLog('完成 StoreKit 交易失败：$error');
    }
  }

  void _addLog(String message) {
    debugPrint('[singular_example] $message');
    if (!mounted) {
      return;
    }
    final now = DateTime.now();
    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, '$timestamp  $message');
      if (_logs.length > 100) {
        _logs.removeLast();
      }
    });
  }

  Widget _buildProductCard(String productId, String eventName) {
    final product = _products[productId];
    final enabled =
        _analyticsReady &&
        _storeAvailable &&
        product != null &&
        _buyingProductId == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(productId, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Singular 事件：$eventName'),
            const SizedBox(height: 4),
            Text(
              product == null
                  ? '尚未从 App Store 加载'
                  : '${product.title} · ${product.price} (${product.currencyCode})',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: enabled ? () => _buy(productId) : null,
              child: Text(
                _buyingProductId == productId ? '请求中…' : '购买 $productId',
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Singular iOS 购买测试')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (!_isIOS)
              const Card(
                color: Color(0xffffe4e4),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('这个 example 仅支持 iOS。'),
                ),
              ),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  '仅用于 App Store Sandbox 联调。示例没有业务服务端验单，'
                  '不要把这里的“假定验证成功”逻辑复制到生产应用。',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('StoreKit 版本', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<StoreKitVersion>(
              segments: const <ButtonSegment<StoreKitVersion>>[
                ButtonSegment<StoreKitVersion>(
                  value: StoreKitVersion.storeKit1,
                  label: Text('StoreKit 1'),
                ),
                ButtonSegment<StoreKitVersion>(
                  value: StoreKitVersion.storeKit2,
                  label: Text('StoreKit 2'),
                ),
              ],
              selected: <StoreKitVersion>{_selectedStoreKitVersion},
              onSelectionChanged: _store == null && !_initializing
                  ? (selection) {
                      setState(() {
                        _selectedStoreKitVersion = selection.single;
                      });
                    }
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              _activeStoreKitVersion == null
                  ? '选择后点击初始化；注册购买监听后将锁定版本。'
                  : '当前使用 ${_activeStoreKitVersion!.label}；切换需重启 App。',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _configUrlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Analytics 远程 JSON',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isIOS && !_initializing
                  ? _initializeAndLoadProducts
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(_initializing ? '初始化中…' : '初始化并加载商品'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isIOS && _store != null && !_loadingProducts
                  ? _loadProducts
                  : null,
              icon: const Icon(Icons.refresh),
              label: Text(_loadingProducts ? '加载中…' : '重新加载商品'),
            ),
            const SizedBox(height: 16),
            _buildProductCard(purchaseProductId, 'sng_ecommerce_purchase'),
            _buildProductCard(yearlySubscriptionId, 'sng_subscribe'),
            _buildProductCard(moreSubscriptionId, 'sng_subscribe'),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Text('运行日志', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton(
                  onPressed: _logs.isEmpty
                      ? null
                      : () => setState(() => _logs.clear()),
                  child: const Text('清空'),
                ),
              ],
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xff111827),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _logs.isEmpty ? '等待操作…' : _logs.join('\n'),
                style: const TextStyle(
                  color: Color(0xffd1fae5),
                  fontFamily: 'Menlo',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreloadedRemoteConfigLoader extends RemoteAnalyticsConfigLoader {
  _PreloadedRemoteConfigLoader(this.result);

  final RemoteAnalyticsConfigResult result;

  @override
  Future<RemoteAnalyticsConfigResult> loadResult(
    RemoteAnalyticsConfig remoteConfig,
  ) async {
    return result;
  }
}
