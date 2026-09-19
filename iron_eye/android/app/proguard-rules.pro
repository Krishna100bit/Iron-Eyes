-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class * extends androidx.room.RoomDatabase
-dontwarn androidx.work.**
-dontwarn androidx.room.**

# ML Kit specific rules to prevent R8 from stripping pose tracking
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_pose_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_mediapipe.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_internal_vkp.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
