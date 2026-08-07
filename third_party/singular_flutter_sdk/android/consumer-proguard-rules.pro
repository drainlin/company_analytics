# Preserve Singular SDK classes. The Singular SDK performs reflective lookups
# on its own classes, and its official Flutter integration docs require keeping
# these names for release (R8) builds. Without this rule, R8 in the host app can
# rename/remove Singular SDK classes and break event reporting.
-keep class com.singular.sdk.** { *; }

# Preserve Google Play Billing class names. The Singular SDK resolves
# com.android.billingclient.api.Purchase reflectively (getSku path), so R8
# renaming it breaks that path, mirroring the Facebook SDK's IAP issue.
-keep class com.android.billingclient.** { *; }
