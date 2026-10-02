import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_exe/data/demo_api.dart';
import 'package:ink_exe/data/models.dart';
import 'package:ink_exe/state/ink_store.dart';
import 'package:ink_exe/state/pen_shop.dart';
import 'package:ink_exe/widget_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 10, 1, 10, 0);
  late DemoInkApi api;
  late InkStore store;

  setUp(() async {
    now = DateTime(2026, 10, 1, 10, 0);
    SharedPreferences.setMockInitialValues({});
    api = DemoInkApi(clock: () => now);
    store = InkStore(api: api, clock: () => now, autoRefresh: false);
    await store.init();
  });

  test('첫 글감과 빈 게시판', () {
    final b = store.board!;
    expect(b.topic, '파란 나무');
    expect(b.count, 0);
    expect(b.cap, 20);
    expect(b.canWrite, isTrue);
    expect(store.secondsLeft, 14 * 3600);
  });

  test('글 올리기 → 자리 · 알림 · 하루 한 편', () async {
    expect(await store.submit('  파란 잎  '), isNull);
    expect(store.board!.mineSlot, 1);
    expect(store.board!.entries.single.body, '파란 잎');
    expect(store.notice!.$2, contains('#01'));
    final again = await store.submit('또');
    expect(again!.code, 'already');
  });

  test('300자 제한 · 인용은 출처 필수', () async {
    expect((await store.submit('가' * 301))!.code, 'too_long');
    expect((await store.submit('구절', kind: EntryKind.quote, title: '데미안'))!.code, 'source');
    expect(await store.submit('가' * 300), isNull);
  });

  test('선착순 20명이 차면 full', () async {
    for (var i = 0; i < 20; i++) {
      await api.postAs('u$i', '글 $i');
    }
    await store.refresh();
    expect(store.board!.full, isTrue);
    expect(store.board!.canWrite, isFalse);
    expect((await store.submit('늦음'))!.code, 'full');
  });

  test('+1 은 바로 반영되고 내 글에는 안 된다', () async {
    await api.postAs('other', '남의 글');
    await store.submit('내 글');
    final other = store.board!.entries.firstWhere((e) => !e.mine);
    final mine = store.board!.entries.firstWhere((e) => e.mine);
    await store.toggleLike(other);
    expect(store.board!.entries.firstWhere((e) => e.id == other.id).likes, 1);
    await store.toggleLike(mine);
    expect(store.board!.entries.firstWhere((e) => e.id == mine.id).likes, 0);
  });

  test('신고 3번이면 가려지고, 차단은 기기에 저장', () async {
    await api.postAs('bad', '나쁜 글');
    final id = api.idOfSlot(1);
    await api.reportAs('a', id);
    await api.reportAs('b', id);
    await store.refresh();
    await store.report(store.board!.entries.first, 'abuse');
    expect(store.board!.entries.first.hidden, isTrue);
    expect(store.board!.entries.first.body, isNull);

    await api.postAs('rude', '무례한 글');
    await store.refresh();
    final e = store.board!.entries.last;
    await store.block(e);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('ink_blocked_v1'), contains(e.author));
  });

  test('신고 한 번이면 내 화면에서 바로 숨기고 기기에 저장', () async {
    await api.postAs('bad', '나쁜 글');
    await store.refresh();
    final e = store.board!.entries.first;
    await store.report(e, 'abuse');
    expect(store.reported, contains(e.id));
    expect(store.board!.entries.first.hidden, isFalse, reason: '다른 사람에겐 3번 쌓여야 가려진다');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('ink_reported_v1'), contains('${e.id}'));
    expect(store.notice!.$2, contains('24시간'));
  });

  test('자정이 지나면 새 글감', () async {
    await store.submit('첫날');
    now = DateTime(2026, 10, 2, 0, 0, 1);
    await store.refresh();
    expect(store.board!.topic, '마지막 버스');
    expect(store.board!.count, 0);
    expect(store.notice!.$2, contains('마지막 버스'));
  });

  test('명예의 전당: 이번 달 날마다 1위 (인용 포함), 다음 달엔 한 편만', () async {
    await api.postAs('a', '창작 1');
    await api.postAs('b', '인용', kind: EntryKind.quote, title: '데미안', author: '헤르만 헤세');
    for (final u in ['x', 'y', 'z']) {
      await api.likeAs(u, api.idOfSlot(2));
    }
    await api.likeAs('x', api.idOfSlot(1));

    now = DateTime(2026, 10, 2, 9);
    await api.postAs('c', '둘째 날 창작');
    for (final u in ['x', 'y']) {
      await api.likeAs(u, api.idOfSlot(1));
    }

    now = DateTime(2026, 10, 3, 9);
    await store.loadHall();
    expect(store.hall.month.map((e) => e.body), ['둘째 날 창작', '인용']);
    expect(store.hall.month.last.source, '— 『데미안』, 헤르만 헤세');
    expect(store.hall.month.last.topic, '파란 나무');

    now = DateTime(2026, 11, 1, 9);
    await store.loadHall();
    expect(store.hall.month, isEmpty);
    expect(store.hall.champions.single.body, '인용');
    expect(store.hall.champions.single.month, '2026.10');
  });

  test('내 글 지우기: 자리는 남는다', () async {
    await store.submit('지울 글');
    final e = store.board!.entries.single;
    await store.deleteMine(e);
    expect(store.board!.entries.single.deleted, isTrue);
    expect(store.board!.count, 1);
    await store.loadMine();
    expect(store.mine.single.deleted, isTrue);
  });

  test('서버 JSON 해석', () {
    final b = Board.fromJson({
      'day': '2026-10-01',
      'is_today': true,
      'topic': '파란 나무',
      'cap': 20,
      'max_len': 300,
      'count': 2,
      'mine_slot': null,
      'banned': false,
      'seconds_left': 100,
      'posts': [
        {
          'id': 7, 'day': '2026-10-01', 'slot': 1, 'nick': 'guest_0042', 'author': 'abc', 'kind': 'quote',
          'body': '새는 알에서', 'src_title': '데미안', 'src_author': '헤르만 헤세', 'likes': 3, 'liked': true,
          'mine': false, 'hidden': false, 'deleted': false, 'time': '00:01',
        },
      ],
    });
    expect(b.left, 18);
    expect(b.entries.single.source, '— 『데미안』, 헤르만 헤세');
    expect(b.entries.single.slotLabel, '#01');
    expect(InkError.fromMessage('ink:full').code, 'full');
    expect(InkError.fromMessage('boom').code, 'network');
    expect(hms(3725), '01:02:05');
  });

  group('펜네임', () {
    late DemoPenShop shop;

    setUp(() async {
      shop = DemoPenShop();
      store = InkStore(api: api, shop: shop, clock: () => now, autoRefresh: false);
      await store.init();
      await store.initPen();
    });

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('사기 전: 이름은 못 정하고 guest 로 올라간다', () async {
      expect(store.pen.owned, isFalse);
      expect(store.penPrice, '₩2,200');
      expect((await store.setPen('작은새'))!.code, 'no_pen');
      await store.submit('그냥 글');
      expect(store.board!.entries.single.nick, startsWith('guest_'));
      expect(store.board!.entries.single.pen, isFalse);
    });

    test('사기 → 서버 확인 → 이름 정하기 → 글에 펜네임', () async {
      await store.buyPen();
      await flush();
      await flush();
      expect(store.pen.owned, isTrue);
      expect(store.pen.name, isNull);
      expect(store.penNotice!.$2, contains('펜네임을 정해'));
      expect(shop.finished, 1, reason: '서버가 받아 준 뒤에만 결제를 마무리한다');

      expect((await store.setPen('작은 새'))!.code, 'pen_chars');
      expect((await store.setPen('guest_1'))!.code, 'pen_reserved');
      api.givePen('other', '달빛');
      expect((await store.setPen('달빛'))!.code, 'pen_taken');
      expect(await store.setPen('작은새_7'), isNull);
      expect(store.pen.name, '작은새_7');
      expect(store.pen.nextChange, isNotNull);
      expect((await store.setPen('큰새'))!.code, 'pen_wait');

      await store.submit('펜네임 글');
      final e = store.board!.entries.single;
      expect(e.nick, '작은새_7');
      expect(e.pen, isTrue);

      now = now.add(const Duration(days: 7, seconds: 1));
      expect(await store.setPen('큰새'), isNull);
    });

    test('서버가 영수증을 거절하면 결제를 마무리하지 않는다 (다음 실행 때 다시)', () async {
      shop.receipt = DemoInkApi.badReceipt;
      await store.buyPen();
      await flush();
      await flush();
      expect(store.pen.owned, isFalse);
      expect(store.penNotice!.$1, 'err');
      expect(shop.finished, 0);
    });

    test('구매 복원: 새 기기(새 사용자)로 펜네임이 옮겨 온다', () async {
      await store.buyPen();
      await flush();
      await flush();
      await store.setPen('작은새');
      api.user = 'new-phone';
      final fresh = InkStore(api: api, shop: shop, clock: () => now, autoRefresh: false);
      await fresh.init();
      await fresh.initPen();
      expect(fresh.pen.owned, isFalse);
      await fresh.restorePen();
      await flush();
      await flush();
      expect(fresh.pen.name, '작은새');
      expect(fresh.penNotice!.$2, contains('복원'));
      fresh.dispose();
    });
  });

  test('화면 모드: 자동은 시스템을 따르고, 다크 · 라이트는 고정 + 저장', () async {
    store.systemBrightness = Brightness.dark;
    expect(store.themeMode, 'auto');
    expect(store.palette.isLight, isFalse);
    store.systemBrightness = Brightness.light;
    expect(store.palette.isLight, isTrue);

    await store.setThemeMode('dark');
    expect(store.palette.isLight, isFalse, reason: '시스템이 라이트여도 다크 고정');
    expect(store.brightness.value, Brightness.dark);

    await store.setThemeMode('light');
    store.systemBrightness = Brightness.dark;
    expect(store.palette.isLight, isTrue, reason: '시스템이 다크여도 라이트 고정');

    final again = InkStore(api: api, clock: () => now, autoRefresh: false);
    await again.loadPrefs();
    expect(again.themeMode, 'light', reason: '앱을 다시 켜도 기억');
    expect(again.brightness.value, Brightness.light);
  });

  test('화면 모드를 바꾸면 위젯에도 알리고, 글을 올리면 위젯을 새로 그린다', () async {
    final w = _FakeWidgets();
    final s2 = InkStore(api: api, widgets: w, clock: () => now, autoRefresh: false);
    await s2.init();
    expect(w.modes, ['auto'], reason: '앱을 켜면 지금 모드를 위젯에 맞춘다');
    await s2.setThemeMode('light');
    expect(w.modes.last, 'light');
    await s2.submit('위젯 새로 고침');
    await Future<void>.delayed(Duration.zero);
    expect(w.reloads, greaterThanOrEqualTo(1));
  });
}

class _FakeWidgets implements WidgetBridge {
  final modes = <String>[];
  int reloads = 0;

  @override
  Future<void> setThemeMode(String mode) async => modes.add(mode);

  @override
  Future<void> reload() async => reloads++;
}
