import 'package:flutter/material.dart';

import '../state/ink_store.dart';
import '../widgets/term_widgets.dart';
import 'hall_screen.dart';
import 'log_screen.dart';
import 'rules_screen.dart';

/// 제목줄 오른쪽 메뉴 `hall  log  규칙`.
///
/// 어느 화면에서든 같은 자리에 같은 순서로 보인다. 지금 화면의 탭만 반전되고,
/// 하위 화면에서 다른 탭을 누르면 뒤로 쌓이지 않게 화면을 바꿔 끼운다.
List<(String, VoidCallback?)> navTabs(BuildContext context, InkStore store, {String? active}) {
  void go(Widget page) {
    final nav = Navigator.of(context);
    if (active == null) {
      nav.push(termRoute(page));
    } else {
      nav.pushReplacement(termRoute(page));
    }
  }

  return [
    ('hall', () => go(HallScreen(store: store))),
    ('log', () => go(LogScreen(store: store))),
    ('규칙', () => go(RulesScreen(store: store, readOnly: true))),
  ];
}
