# Flutter engine + plugin registry
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Keep annotations and plugin method entry points
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# flutter_secure_storage uses androidx.security which reflects on Tink types
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# amazon_cognito_identity_dart_2 is pure Dart but may pull JDK types
-dontwarn javax.annotation.**

# flutter_local_notifications + GSON TypeToken reflection
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature

# Our own method channel entry points
-keep class com.scobysense.app.** { *; }
