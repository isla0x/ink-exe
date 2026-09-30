import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 이 기기를 가리키는 ID. 앱을 지웠다 다시 깔아도 같게 유지된다.
///   iOS    : 키체인에 저장한 UUID (ios/Runner/AppDelegate.swift)
///   Android: ANDROID_ID (android/.../MainActivity.kt)
/// 서버(bind_device)는 이 값을 해시로만 저장하고, 하루 한 편 · +1 · 신고를 기기 단위로 센다.
class DeviceId {
  static const _channel = MethodChannel('ink/device');
  static const _fallbackKey = 'ink_device_fallback_v1';

  static Future<String?> get() async {
    if (!kIsWeb) {
      try {
        final id = await _channel.invokeMethod<String>('deviceId');
        if (id != null && id.length >= 8) return id;
      } catch (e) {
        debugPrint('ink.exe: 기기 ID 를 읽지 못함 ($e)');
      }
    }
    // 네이티브 쪽을 못 쓰면 앱 저장소에 만든 값 (다시 깔면 바뀐다).
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_fallbackKey);
    if (id == null) {
      final r = Random.secure();
      id = 'app-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
      await prefs.setString(_fallbackKey, id);
    }
    return id;
  }
}
