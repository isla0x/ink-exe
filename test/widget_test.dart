import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_exe/data/demo_api.dart';
import 'package:ink_exe/main.dart';
import 'package:ink_exe/state/ink_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late DemoInkApi api;
  late InkStore store;
  final now = DateTime(2026, 10, 1, 10, 0);

  Future<void> boot(WidgetTester tester, {bool agreed = false, int others = 0}) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'ink_rules_v1': agreed});
    api = DemoInkApi(clock: () => now);
    for (var i = 0; i < others; i++) {
      await api.postAs('u$i', '다른 사람 글 $i');
    }
    store = InkStore(api: api, clock: () => now, autoRefresh: false);
    await store.init();
    await tester.pumpWidget(InkExeApp(store: store));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('규칙 동의 → 게시판 → 글쓰기', (tester) async {
    await boot(tester);
    expect(find.text('오늘의 글감 게시판'), findsOneWidget);

    // 체크 전에는 입장 버튼이 막혀 있다.
    await tester.tap(find.text('입장하기'), warnIfMissed: false);
    await settle(tester);
    expect(find.text('오늘의 글감 게시판'), findsOneWidget);

    await tester.tap(find.text('위 규칙과 이용약관에 동의하고, 만 14세 이상이에요.'));
    await tester.pump();
    await tester.tap(find.text('입장하기'));
    await settle(tester);

    expect(find.text('파란 나무'), findsOneWidget);
    expect(find.text('0/20'), findsOneWidget);
    expect(find.text('아직 아무도 안 썼어요. 첫 자리를 잡아 보세요.'), findsOneWidget);

    await tester.tap(find.text('쓰기'));
    await settle(tester);
    expect(find.textContaining('write #01'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '파란 잎이 떨어졌다');
    await tester.pump();
    expect(find.text('10/300'), findsOneWidget);
    await tester.tap(find.text('올리기'));
    await settle(tester);

    expect(find.text('파란 잎이 떨어졌다'), findsOneWidget);
    expect(find.textContaining('#01 자리에 올렸어요'), findsOneWidget);
    expect(find.textContaining('✓ 오늘 #01 에 올렸어요'), findsOneWidget);
    expect(find.text('1/20'), findsOneWidget);
  });

  testWidgets('인용은 작품명 · 작가가 있어야 올라간다', (tester) async {
    await boot(tester, agreed: true);
    await tester.tap(find.text('쓰기'));
    await settle(tester);
    await tester.tap(find.text('인용'));
    await tester.pump();

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(3));
    await tester.enterText(fields.at(2), '새는 알에서 나오려고 투쟁한다.');
    await tester.pump();
    await tester.tap(find.text('올리기'), warnIfMissed: false);
    await settle(tester);
    expect(find.textContaining('write #01'), findsOneWidget, reason: '출처 없이는 버튼이 막혀 있다');

    await tester.enterText(fields.at(0), '데미안');
    await tester.enterText(fields.at(1), '헤르만 헤세');
    await tester.pump();
    await tester.tap(find.text('올리기'));
    await settle(tester);

    expect(find.text('[인용]'), findsOneWidget);
    expect(find.text('— 『데미안』, 헤르만 헤세'), findsOneWidget);
  });

  testWidgets('20자리가 차면 Server is full', (tester) async {
    await boot(tester, agreed: true, others: 20);
    expect(find.text('Server is full.'), findsOneWidget);
    expect(find.text('FULL'), findsOneWidget);
    expect(find.text('쓰기'), findsNothing);
  });

  testWidgets('+1 과 차단', (tester) async {
    await boot(tester, agreed: true, others: 1);
    expect(find.text('+0'), findsOneWidget);
    await tester.tap(find.text('+0'));
    await tester.pump();
    expect(find.text('+1'), findsOneWidget);

    await tester.tap(find.text('⋯'));
    await settle(tester);
    expect(find.text('저작권 문제 (출처 없는 인용 등)'), findsOneWidget);
    await tester.tap(find.text('이 사람 글 안 보기 (차단)'));
    await settle(tester);
    expect(find.text('(차단한 사람의 글)'), findsOneWidget);
  });

  testWidgets('메뉴는 어느 화면에서든 같은 자리에 있고, 누른 탭만 반전된다', (tester) async {
    await boot(tester, agreed: true);
    final x = {for (final t in ['hall', 'log', '규칙']) t: tester.getCenter(find.text(t)).dx};

    Future<void> tapAndCheck(String tab) async {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      for (final t in x.keys) {
        expect(find.text(t), findsOneWidget, reason: '$tab 화면에도 $t 탭이 있다');
        expect(tester.getCenter(find.text(t)).dx, x[t], reason: '$t 탭 자리가 그대로다');
      }
    }

    await tapAndCheck('hall');
    expect(find.text('명예의 전당'), findsOneWidget);
    await tapAndCheck('log');
    expect(find.textContaining('내가 쓴 글'), findsOneWidget);
    await tapAndCheck('규칙');
    expect(find.text('오늘의 글감 게시판'), findsOneWidget);

    // 탭끼리 옮겨 다녀도 뒤로 한 번이면 게시판이다.
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    expect(find.text('쓰기'), findsOneWidget);
  });
}
