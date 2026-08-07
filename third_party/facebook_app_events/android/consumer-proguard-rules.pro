# Preserve Facebook App Events classes used by this plugin.
# Without this rule, R8 in the host app may strip App Events classes that are
# only referenced reflectively by the Facebook App Events SDK, causing runtime crashes.
-keep class com.facebook.appevents.** { *; }

# Preserve Google Play Billing library class names. The Facebook SDK's IAP
# auto-logging wrapper resolves Billing classes reflectively by name
# (Class.forName("com.android.billingclient.api.BillingClient")), so R8
# renaming them breaks auto-IAP logging ("Failed to create Google Play billing
# library wrapper"). Keep original names so the reflection lookups succeed.
-keep class com.android.billingclient.** { *; }
