# Flutter release builds run R8 (minify on by default in the Flutter Gradle
# plugin, which picks this file up by name).
#
# flutter_local_notifications persists scheduled notifications with Gson and
# reads them back through TypeToken generics. R8 strips the generic signatures
# and the model fields, so a release build crashes or silently drops the
# schedule ("Missing type parameter") when rescheduling after reboot or update.
-keep class com.dexterous.** { *; }

# Gson (https://github.com/google/gson/blob/main/examples/android-proguard-example/proguard.cfg)
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-dontwarn sun.misc.**
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
