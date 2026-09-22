package com.bijbelstudie.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes the running Android API level to Dart.
 *
 * Android 15 (API 35) deprecated Window.setStatusBarColor,
 * setNavigationBarColor, setNavigationBarDividerColor and
 * setNavigationBarContrastEnforced, and ignores all four under the
 * edge-to-edge enforcement that applies to every app targeting SDK 35+.
 * Flutter's PlatformPlugin only calls them when the matching field of a
 * SystemUiOverlayStyle is non-null, so AppTheme leaves those fields null once
 * it knows the device is on 35 or newer, and keeps setting them below that -
 * on API 24..34 they are the only way to keep both system bars transparent.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "com.bijbelstudie.app/platform"
    }
}
