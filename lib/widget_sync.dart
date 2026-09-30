import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// 앱 → 홈 화면 위젯(iOS WidgetKit, ios/InkWidget).
///
/// 위젯은 게시판 요약을 서버에서 직접 받지만, 화면 모드(auto · dark · light)는 앱 설정을 따라야 해서
/// App Group 저장소에 넣어 준다. Runner 와 InkWidget 두 타깃 모두 [appGroupId] 로 App Groups 가 켜져 있다.
abstract class WidgetBridge {
  Future<void> setThemeMode(String mode);

  /// 위젯을 바로 새로 그리게 한다 (글을 올린 뒤 등).
  Future<void> reload();
}

class WidgetSync implements WidgetBridge {
  static const appGroupId = 'group.com.isla0x.inkexe';
  static const iOSWidgetKind = 'InkWidget';
  static const modeKey = 'mode';

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<WidgetSync?> create() async {
    if (!supported) return null;
    try {
      await HomeWidget.setAppGroupId(appGroupId);
      return WidgetSync();
    } catch (e) {
      debugPrint('ink.exe widget: setAppGroupId 실패 ($e)');
      return null;
    }
  }

  @override
  Future<void> setThemeMode(String mode) async {
    try {
      await HomeWidget.saveWidgetData<String>(modeKey, mode);
      await reload();
    } catch (e) {
      // 위젯이 없거나 App Group 이 꺼져 있어도 앱은 계속 동작해야 한다.
      debugPrint('ink.exe widget: 저장 실패 ($e)');
    }
  }

  @override
  Future<void> reload() async {
    try {
      await HomeWidget.updateWidget(iOSName: iOSWidgetKind);
    } catch (e) {
      debugPrint('ink.exe widget: 새로 고침 실패 ($e)');
    }
  }
}
