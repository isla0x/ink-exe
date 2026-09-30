package com.isla0x.ink_exe

import android.annotation.SuppressLint
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 기기 ID: 앱을 지웠다 다시 깔아도 같은 값 (서명 키 · 사용자별). 서버에는 해시로만 저장된다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ink/device").setMethodCallHandler { call, result ->
            if (call.method == "deviceId") {
                @SuppressLint("HardwareIds")
                val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                result.success(id)
            } else {
                result.notImplemented()
            }
        }
    }
}
