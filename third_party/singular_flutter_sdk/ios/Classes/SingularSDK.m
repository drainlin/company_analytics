#import <Singular/Singular.h>
#import <Singular/SingularConfig.h>
#import <Singular/SingularLinkParams.h>
#import <StoreKit/StoreKit.h>
#import "SingularAppDelegate.h"
#import "SingularConstants.h"
#import "SingularSDK.h"

@implementation SingularSDK

static FlutterMethodChannel *channel;
static NSDictionary *configDict;
static BOOL singularFlutterLoggingEnabled = NO;

#define SINGULAR_FLUTTER_LOG(format, ...) \
    do { \
        if (singularFlutterLoggingEnabled) { \
            NSLog((format), ##__VA_ARGS__); \
        } \
    } while (0)

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
    channel = [FlutterMethodChannel methodChannelWithName:@"singular-api" binaryMessenger:[registrar messenger]];

    SingularSDK *instance = [[SingularSDK alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([START isEqualToString:call.method]) {
        [self start:call withResult:result];
    } else if ([EVENT isEqualToString:call.method]) {
        [self event:call withResult:result];
    } else if ([EVENT_WITH_ARGS isEqualToString:call.method]) {
        [self eventWithArgs:call withResult:result];
    } else if ([STOREKIT1_IN_APP_PURCHASE isEqualToString:call.method]) {
        [self storeKit1InAppPurchase:call withResult:result];
    } else if ([SET_CUSTOM_USER_ID isEqualToString:call.method]) {
        [self setCustomUserId:call withResult:result];
    } else if ([UNSET_CUSTOM_USER_ID isEqualToString:call.method]) {
        [Singular unsetCustomUserId];
        result(nil);
    } else if ([SET_DEVICE_CUSTOM_USER_ID isEqualToString:call.method]) {
        [self setDeviceCustomUserId:call withResult:result];
    } else if ([REGISTER_DEVICE_TOKEN_FOR_UNINSTALL isEqualToString:call.method]) {
        [self registerDeviceTokenForUninstall:call withResult:result];
    } else if ([CUSTOM_REVENUE isEqualToString:call.method]) {
        [self customRevenue:call withResult:result];
    } else if ([CUSTOM_REVENUE_WITH_ATTRIBUTES isEqualToString:call.method]) {
        [self customRevenueWithAttributes:call withResult:result];
    } else if ([CUSTOM_REVENUE_WITH_ALL_ATTRIBUTES isEqualToString:call.method]) {
        [self customRevenueWithAllAttributes:call withResult:result];
    } else if ([SET_WRAPPER_NAME_AND_VERSION isEqualToString:call.method]) {
        [self setWrapperNameAndVersion:call withResult:result];
    } else if ([GET_GLOBAL_PROPERTIES isEqualToString:call.method]) {
        result([Singular getGlobalProperties]);
    } else if ([SET_GLOBAL_PROPERTY isEqualToString:call.method]) {
        [self setGlobalProperty:call withResult:result];
    } else if ([UNSET_GLOBAL_PROPERTY isEqualToString:call.method]) {
        [self unsetGlobalProperty:call withResult:result];
    } else if ([CLEAR_GLOBAL_PROPERTIES isEqualToString:call.method]) {
        [Singular clearGlobalProperties];
    } else if ([TRACKING_OPT_IN isEqualToString:call.method]) {
        [Singular trackingOptIn];
    } else if ([TRACKING_UNDER13 isEqualToString:call.method]) {
        [Singular trackingUnder13];
    } else if ([STOP_ALL_TRACKING isEqualToString:call.method]) {
        [Singular stopAllTracking];
    } else if ([RESUME_ALL_TRACKING isEqualToString:call.method]) {
        [Singular resumeAllTracking];
    } else if ([IS_ALL_TRACKING_STOPPED isEqualToString:call.method]) {
        result(@([Singular isAllTrackingStopped]));
    } else if ([LIMIT_DATA_SHARING isEqualToString:call.method]) {
        [self limitDataSharing:call withResult:result];
    } else if ([GET_LIMIT_DATA_SHARING isEqualToString:call.method]) {
        result(@([Singular getLimitDataSharing]));
    } else if ([SKAN_REGISTER_APP_FOR_AD_ATTRIBUTION isEqualToString:call.method]) {
        [Singular skanRegisterAppForAdNetworkAttribution];
    } else if ([SKAN_UPDATE_CONVERSION_VALUE isEqualToString:call.method]) {
        [self skanUpdateConversionValue:call withResult:result];
    } else if ([SKAN_UPDATE_CONVERSION_VALUES isEqualToString:call.method]) {
        [self skanUpdateConversionValues:call withResult:result];
    } else if ([SKAN_GET_CONVERSION_VALUE isEqualToString:call.method]) {
        [self skanGetConversionValue:call withResult:result];
    } else if ([CREATE_REFERRER_SHORT_LINK isEqualToString:call.method]) {
        [self createReferrerShortLink:call withResult:result];
    } else if ([HANDLE_PUSH_NOTIFICATION isEqualToString:call.method]) {
        [self handlePushNotification:call withResult:result];
    } else if ([SET_LIMIT_ADVERTISING_IDENTIFIERS isEqualToString:call.method]) {
        [self setLimitAdvertisingIdentifiers:call withResult:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

+ (void)initializeSingular {
    [SingularSDK initSDK];
}

+ (void)initSDK {
    if (configDict == nil) {
        return;
    }

    NSString *apiKey = configDict[@"apiKey"];
    NSString *secretKey = configDict[@"secretKey"];
    BOOL skAdNetworkEnabled = [configDict[@"skAdNetworkEnabled"] boolValue];
    BOOL clipboardAttribution = [configDict[@"clipboardAttribution"] boolValue];
    BOOL manualSkanConversionManagement = [configDict[@"manualSkanConversionManagement"] boolValue];
    int waitForTrackingAuthorizationWithTimeoutInterval = [configDict[@"waitForTrackingAuthorizationWithTimeoutInterval"] intValue];
    float shortLinkResolveTimeOut = [configDict[@"shortLinkResolveTimeOut"] floatValue];
    NSString *customUserId = configDict[@"customUserId"];
    BOOL limitAdvertisingIdentifiers = [configDict[@"limitAdvertisingIdentifiers"] boolValue];
    BOOL enableLogging = [configDict[@"enableLogging"] boolValue];
    NSInteger requestedLogLevel = [configDict[@"logLevel"] integerValue];
    singularFlutterLoggingEnabled = enableLogging;

    SingularConfig *config = [[SingularConfig alloc] initWithApiKey:apiKey andSecret:secretKey];
    config.skAdNetworkEnabled = skAdNetworkEnabled;
    config.clipboardAttribution = clipboardAttribution;
    config.manualSkanConversionManagement = manualSkanConversionManagement;
    config.waitForTrackingAuthorizationWithTimeoutInterval = waitForTrackingAuthorizationWithTimeoutInterval;
    config.shortLinkResolveTimeOut = shortLinkResolveTimeOut;
    config.espDomains = configDict[@"espDomains"];
    config.brandedDomains = configDict[@"brandedDomains"];
    config.limitAdvertisingIdentifiers = limitAdvertisingIdentifiers;
    config.enableOdmWithTimeoutInterval = [configDict[@"enableOdmWithTimeoutInterval"] intValue];
    config.enableLogging = enableLogging;
    if (requestedLogLevel >= SingularLogLevelNone &&
        requestedLogLevel <= SingularLogLevelVerbose) {
        config.logLevel = (SingularLogLevel)requestedLogLevel;
    } else if (enableLogging) {
        config.logLevel = SingularLogLevelVerbose;
    }

    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] Configuring Singular enableLogging=%@ logLevel=%ld waitForATT=%d skAdNetwork=%@ limitDataSharing=%@",
          enableLogging ? @"YES" : @"NO",
          (long)config.logLevel,
          waitForTrackingAuthorizationWithTimeoutInterval,
          skAdNetworkEnabled ? @"YES" : @"NO",
          configDict[@"limitDataSharing"] ?: @"null");

    NSArray *props = configDict[@"globalProperties"];

    if (props != nil) {
        for (NSDictionary *prop in props) {
            NSString *key = [prop objectForKey:@"key"];
            NSString *value = [prop objectForKey:@"value"];
            BOOL overrideExisting = [[prop objectForKey:@"overrideExisting"]boolValue];
            [config setGlobalProperty:key withValue:value overrideExisting:overrideExisting];
        }
    }

    if (customUserId) {
        [Singular setCustomUserId:customUserId];
    }

    NSNumber *limitDataSharing = configDict[@"limitDataSharing"];

    if (![limitDataSharing isEqual:[NSNull null]]) {
        [Singular limitDataSharing:[limitDataSharing boolValue]];
    }

    NSNumber *sessionTimeout = configDict[@"sessionTimeout"];

    if ([sessionTimeout intValue] >= 0) {
        [Singular setSessionTimeout:[sessionTimeout intValue]];
    }

    config.singularLinksHandler = ^(SingularLinkParams *params) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *linkParams = [[NSMutableDictionary alloc] init];
            [linkParams setValue:[params getDeepLink] forKey:@"deeplink"];
            [linkParams setValue:[params getPassthrough] forKey:@"passthrough"];
            [linkParams setValue:@([params isDeferred]) forKey:@"isDeferred"];
            [linkParams setValue:([params getUrlParameters] ? [params getUrlParameters] : @{ }) forKey:@"urlParameters"];

            [channel invokeMethod:@"singularLinksHandlerName" arguments:linkParams];
        });
    };
    
    if ([SingularAppDelegate shared].launchOptions != nil) {
        config.launchOptions = [SingularAppDelegate shared].launchOptions;
    } else if ([SingularAppDelegate shared].userActivity != nil) {
        config.userActivity = [SingularAppDelegate shared].userActivity;
    } else if ([SingularAppDelegate shared].openURL != nil) {
        config.openUrl = [SingularAppDelegate shared].openURL;
    } else {
        NSLog(@"everything is null");
    }

    config.deviceAttributionCallback = ^(NSDictionary *attributionInfo) {
        NSString *attributionData = [self dictionaryToJson:attributionInfo];
        if (attributionData != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [channel invokeMethod:@"deviceAttributionCallbackName" arguments:attributionData];
            });
        }
    };

    config.conversionValueUpdatedCallback = ^(NSInteger conversionValue) {
        NSString *conversionValueUpdatedCallback = configDict[@"conversionValueUpdatedCallback"];

        if (conversionValueUpdatedCallback != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [channel invokeMethod:@"conversionValueUpdatedCallbackName" arguments:@(conversionValue)];
            });
        }
    };

    config.conversionValuesUpdatedCallback = ^(NSNumber *conversionValue, NSNumber *coarse, BOOL lock) {
        NSString *conversionValuesUpdatedCallback = configDict[@"conversionValuesUpdatedCallback"];

        if (conversionValuesUpdatedCallback != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableDictionary *updatedConversionValues = [[NSMutableDictionary alloc] init];
                [updatedConversionValues setValue:(conversionValue != nil) ? @([conversionValue integerValue]) : @(-1) forKey:@"conversionValue"];
                [updatedConversionValues setValue:(coarse != nil) ? @([coarse integerValue]) : @(-1) forKey:@"coarse"];
                [updatedConversionValues setValue:@(lock) forKey:@"lock"];

                [channel invokeMethod:@"conversionValuesUpdatedCallbackName" arguments:updatedConversionValues];
            });
        }
    };
    
    NSString *customSdid = configDict[@"customSdid"];
    config.customSdid = customSdid;
    config.sdidReceivedHandler = ^(NSString *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [channel invokeMethod:@"sdidReceivedCallbackName" arguments:result];
        });
    };

    config.didSetSdidHandler = ^(NSString *result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [channel invokeMethod:@"didSetSdidCallbackName" arguments:result];
        });
    };
    
    config.pushNotificationLinkPath = configDict[@"pushNotificationsLinkPaths"];;

    BOOL started = [Singular start:config];
    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] Singular start returned=%@ sessionStarted=%@ sdkVersion=%@",
          started ? @"YES" : @"NO",
          [Singular sessionStarted] ? @"YES" : @"NO",
          [Singular version]);
}

+ (NSString *)dictionaryToJson:(NSDictionary *)data {
    NSError *error;
    NSData *JSON = [NSJSONSerialization dataWithJSONObject:data options:0 error:&error];
    if (error) {
        return nil;
    }
    
    NSString *JSONString = [[NSString alloc] initWithData:JSON encoding:NSUTF8StringEncoding];
    return JSONString;
}

- (void)start:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    configDict = call.arguments;
    [SingularSDK initSDK];
    result(nil);
}

- (void)event:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName =  call.arguments[@"eventName"];

    [Singular event:eventName];
    result(nil);
}

- (void)eventWithArgs:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName =  call.arguments[@"eventName"];
    NSDictionary *args = call.arguments[@"args"];

    NSString *receipt = [args[@"ptr"] isKindOfClass:[NSString class]] ? args[@"ptr"] : nil;
    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] eventWithArgs name=%@ keys=%@ revenue=%@ currency=%@ product=%@ transaction=%@ receiptLength=%lu sessionStarted=%@",
          eventName,
          [[args allKeys] componentsJoinedByString:@","],
          args[@"r"] ?: @"null",
          args[@"pcc"] ?: @"null",
          args[@"pk"] ?: @"null",
          args[@"pti"] ?: @"null",
          (unsigned long)receipt.length,
          [Singular sessionStarted] ? @"YES" : @"NO");

    [Singular event:eventName withArgs:args];
    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] eventWithArgs queued name=%@", eventName);
    result(nil);
}

- (void)storeKit1InAppPurchase:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName = call.arguments[@"eventName"];
    NSString *transactionId = call.arguments[@"transactionId"];
    NSString *productId = call.arguments[@"productId"];

    if (![eventName isKindOfClass:[NSString class]] || eventName.length == 0 ||
        ![transactionId isKindOfClass:[NSString class]] || transactionId.length == 0 ||
        ![productId isKindOfClass:[NSString class]] || productId.length == 0) {
        SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] StoreKit1 IAP rejected invalid arguments event=%@ product=%@ transaction=%@",
              eventName, productId, transactionId);
        result([FlutterError errorWithCode:@"singular_storekit1_invalid_arguments"
                                   message:@"StoreKit 1 IAP requires eventName, productId, and transactionId."
                                   details:nil]);
        return;
    }

    NSArray<SKPaymentTransaction *> *transactions = [SKPaymentQueue defaultQueue].transactions;
    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] StoreKit1 IAP lookup event=%@ product=%@ transaction=%@ queueCount=%lu sessionStarted=%@",
          eventName,
          productId,
          transactionId,
          (unsigned long)transactions.count,
          [Singular sessionStarted] ? @"YES" : @"NO");

    SKPaymentTransaction *matchedTransaction = nil;
    for (SKPaymentTransaction *transaction in transactions) {
        NSString *queuedTransactionId = transaction.transactionIdentifier ?: @"null";
        NSString *queuedProductId = transaction.payment.productIdentifier ?: @"null";
        SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] StoreKit1 queue item product=%@ transaction=%@ state=%ld",
              queuedProductId,
              queuedTransactionId,
              (long)transaction.transactionState);
        if ([queuedTransactionId isEqualToString:transactionId] &&
            [queuedProductId isEqualToString:productId]) {
            matchedTransaction = transaction;
            break;
        }
    }

    if (matchedTransaction == nil) {
        SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] StoreKit1 IAP transaction not found product=%@ transaction=%@",
              productId, transactionId);
        result([FlutterError errorWithCode:@"singular_storekit1_transaction_not_found"
                                   message:@"The StoreKit 1 transaction is no longer present in SKPaymentQueue."
                                   details:@{
                                       @"productId": productId,
                                       @"transactionId": transactionId,
                                       @"queueCount": @(transactions.count),
                                   }]);
        return;
    }

    if (matchedTransaction.transactionState != SKPaymentTransactionStatePurchased) {
        SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] StoreKit1 IAP wrong state=%ld product=%@ transaction=%@",
              (long)matchedTransaction.transactionState, productId, transactionId);
        result([FlutterError errorWithCode:@"singular_storekit1_transaction_not_purchased"
                                   message:@"The StoreKit 1 transaction is not in the purchased state."
                                   details:@{
                                       @"productId": productId,
                                       @"transactionId": transactionId,
                                       @"state": @(matchedTransaction.transactionState),
                                   }]);
        return;
    }

    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] Calling Singular iapComplete:withName: product=%@ transaction=%@ event=%@",
          productId, transactionId, eventName);
    [Singular iapComplete:matchedTransaction withName:eventName];
    [Singular sendAllBatches];
    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] Singular native StoreKit1 IAP queued and flush requested product=%@ transaction=%@ event=%@",
          productId, transactionId, eventName);

    result(@{
        @"status": @"queued_to_singular_native_sdk",
        @"eventName": eventName,
        @"productId": productId,
        @"transactionId": transactionId,
        @"queueCount": @(transactions.count),
    });
}

- (void)setCustomUserId:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *customUserId = call.arguments[@"customUserId"];

    [Singular setCustomUserId:customUserId];
    result(nil);
}

- (void)setDeviceCustomUserId:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *customUserId = call.arguments[@"customUserId"];

    [Singular setDeviceCustomUserId:customUserId];
}

- (void)registerDeviceTokenForUninstall:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *deviceToken = call.arguments[@"deviceToken"];
    NSData *tokenData = [self convertHexStringToDataBytes:deviceToken];
    if (tokenData) {
        [Singular registerDeviceTokenForUninstall:tokenData];
    }
}

- (void)customRevenue:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName =  call.arguments[@"eventName"];
    NSString *currency =  call.arguments[@"currency"];
    double amount = [call.arguments[@"amount"] doubleValue];

    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] customRevenue name=%@ currency=%@ amount=%f sessionStarted=%@",
          eventName, currency, amount, [Singular sessionStarted] ? @"YES" : @"NO");
    [Singular customRevenue:eventName currency:currency amount:amount];
    result(nil);
}

- (void)customRevenueWithAttributes:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName =  call.arguments[@"eventName"];
    NSString *currency =  call.arguments[@"currency"];
    double amount = [call.arguments[@"amount"] doubleValue];
    NSDictionary *attributes = call.arguments[@"attributes"];

    SINGULAR_FLUTTER_LOG(@"[SingularFlutter][iOS] customRevenueWithAttributes name=%@ currency=%@ amount=%f keys=%@ sessionStarted=%@",
          eventName,
          currency,
          amount,
          [[attributes allKeys] componentsJoinedByString:@","],
          [Singular sessionStarted] ? @"YES" : @"NO");
    [Singular customRevenue:eventName currency:currency amount:amount withAttributes:attributes];
    result(nil);
}

- (void)customRevenueWithAllAttributes:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *eventName =  call.arguments[@"eventName"];
    NSString *currency =  call.arguments[@"currency"];
    double amount = [call.arguments[@"amount"] doubleValue];
    NSString *productSKU = call.arguments[@"productSKU"];
    NSString *productName = call.arguments[@"productName"];
    NSString *productCategory = call.arguments[@"productCategory"];
    int productQuantity = [call.arguments[@"productQuantity"] intValue];
    double productPrice = [call.arguments[@"productPrice"] doubleValue];

    [Singular customRevenue:eventName currency:currency amount:amount productSKU:productSKU productName:productName productCategory:productCategory productQuantity:productQuantity productPrice:productPrice];
}

- (void)createReferrerShortLink:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *baseLink =  call.arguments[@"baseLink"];
    NSString *referrerName =  call.arguments[@"referrerName"];
    NSString *referrerId =  call.arguments[@"referrerId"];
    NSDictionary *args = call.arguments[@"args"];

    [Singular createReferrerShortLink:baseLink
                         referrerName:referrerName
                           referrerId:referrerId
                    passthroughParams:args
                    completionHandler:^(NSString *data, NSError *error) {
        NSMutableDictionary *linkParams = [[NSMutableDictionary alloc] init];

        if (data != nil) {
            [linkParams setValue:data
                          forKey:@"data"];
        }

        if (error != nil) {
            [linkParams setValue:error.description
                          forKey:@"error"];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [channel invokeMethod:@"shortLinkCallbackName"
                        arguments:linkParams];
        });
    }];
}

- (void)setWrapperNameAndVersion:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *wrapperName =  call.arguments[@"name"];
    NSString *version =  call.arguments[@"version"];

    [Singular setWrapperName:wrapperName andVersion:version];
}

- (void)setGlobalProperty:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *key =  call.arguments[@"key"];
    NSString *value =  call.arguments[@"value"];
    BOOL overrideExisting =  [call.arguments[@"overrideExisting"] boolValue];

    result(@([Singular setGlobalProperty:key andValue:value overrideExisting:overrideExisting]));
}

- (void)unsetGlobalProperty:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *key =  call.arguments[@"key"];

    [Singular unsetGlobalProperty:key];
}

- (void)limitDataSharing:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    BOOL shouldLimitDataSharing =  [call.arguments[@"limitDataSharing"] boolValue];

    [Singular limitDataSharing:shouldLimitDataSharing];
}

- (void)skanUpdateConversionValue:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *conversionValue =  call.arguments[@"conversionValue"];

    if ([self isFieldValid:conversionValue]) {
        result(@([Singular skanUpdateConversionValue:[conversionValue integerValue]]));
    }
}

- (void)skanUpdateConversionValues:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSString *conversionValue =  call.arguments[@"conversionValue"];
    NSString *coarse =  call.arguments[@"coarse"];
    BOOL lock =  [call.arguments[@"lock"] boolValue];

    [Singular skanUpdateConversionValue:[conversionValue integerValue] coarse:[coarse integerValue] lock:lock];
}

- (void)skanGetConversionValue:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    result([Singular skanGetConversionValue]);
}

- (void)handlePushNotification:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    NSDictionary *pushNotificationPayload = call.arguments[@"pushNotificationPayload"];
    [Singular handlePushNotification:pushNotificationPayload];
}

- (void)setLimitAdvertisingIdentifiers:(FlutterMethodCall *)call withResult:(FlutterResult)result {
    BOOL limitAdvertisingIdentifiers =  [call.arguments[@"limitAdvertisingIdentifiers"] boolValue];
    [Singular setLimitAdvertisingIdentifiers:limitAdvertisingIdentifiers];
}

- (BOOL)isFieldValid:(NSObject *)field {
    if (field == nil) {
        return NO;
    }

    // Check if its an instance of the singleton NSNull.
    if ([field isKindOfClass:[NSNull class]]) {
        return NO;
    }

    // If field can be converted to a string, check if it has any content.
    NSString *str = [NSString stringWithFormat:@"%@", field];

    if (str != nil) {
        if ([str length] == 0) {
            return NO;
        }
    }

    return YES;
}

- (NSData *)convertHexStringToDataBytes:(NSString *)hexString {
    if([hexString length] % 2 != 0) {
        return nil;
    }

    const char *chars = [hexString UTF8String];
    int index = 0, length = (int)[hexString length];

    NSMutableData *data = [NSMutableData dataWithCapacity:length / 2];
    char byteChars[3] = {'\0','\0','\0'};
    unsigned long wholeByte;

    while (index < length) {
        byteChars[0] = chars[index++];
        byteChars[1] = chars[index++];
        wholeByte = strtoul(byteChars, NULL, 16);
        [data appendBytes:&wholeByte length:1];
    }
    
    return data;
}

@end
