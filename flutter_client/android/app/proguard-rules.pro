# Flutter + Play R8
# allowoptimization: keep names for JNI, but let R8 strip deprecated
# Window.setStatusBarColor / setNavigationBarColor calls inside the embedding.
-keep,allowoptimization class io.flutter.app.** { *; }
-keep,allowoptimization class io.flutter.plugin.** { *; }
-keep,allowoptimization class io.flutter.util.** { *; }
-keep,allowoptimization class io.flutter.view.** { *; }
-keep,allowoptimization class io.flutter.** { *; }
-keep,allowoptimization class io.flutter.plugins.** { *; }

# Play Android 15 static scan: remove invoke-virtual of these from DEX.
-assumenosideeffects class android.view.Window {
    public void setStatusBarColor(int);
    public void setNavigationBarColor(int);
    public void setNavigationBarDividerColor(int);
}

-keep class vn.sana.sbox.** { *; }

-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
