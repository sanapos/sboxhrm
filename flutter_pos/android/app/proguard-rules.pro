# ProGuard / R8 — giữ tối thiểu cho Flutter + Sunmi printer (nếu có).
-keep class woyou.aidlservice.jiuiv5.** { *; }
-dontwarn woyou.aidlservice.jiuiv5.**

# Sunmi DSKernel (màn phụ T1) + GreenDAO entities trong DS_Lib
-keep class sunmi.ds.** { *; }
-keep class com.sunmi.aidl.** { *; }
-keep class org.greenrobot.greendao.** { *; }
-keepclassmembers class * extends org.greenrobot.greendao.AbstractDao {
    public static java.lang.String TABLENAME;
}
-keep class **$Properties { *; }
-dontwarn sunmi.ds.**
-dontwarn org.greenrobot.greendao.**
-dontwarn com.alibaba.fastjson.**
