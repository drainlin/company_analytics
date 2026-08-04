import 'package:company_analytics_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configures one purchase and two subscription products', () {
    expect(productIds, <String>[
      purchaseProductId,
      yearlySubscriptionId,
      moreSubscriptionId,
    ]);
    expect(purchaseProductId, 'test.1000');
    expect(yearlySubscriptionId, 'test.year');
    expect(moreSubscriptionId, 'test.more1');
  });
}
