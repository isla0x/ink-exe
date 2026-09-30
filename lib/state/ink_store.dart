import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Brightness;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ink_api.dart';
import '../data/models.dart';
import '../theme/term_palette.dart';
import '../widget_sync.dart';
import 'pen_shop.dart';

/// 앱 상태: 게시판을 불러오고, 글 · +1 · 신고 · 차단을 처리한다.
class InkStore extends ChangeNotifier {
  InkStore({required this.api, this.shop, this.widgets, DateTime Function()? clock, this.autoRefresh = true})
      : _clock = clock ?? DateTime.now;

  final InkApi api;

  /// 펜네임 결제 창구. null 이면 이 기기에서는 펜네임을 살 수 없다 (안드로이드 등).
  final PenShop? shop;

  /// 홈 화면 위젯. null 이면 위젯 없음 (안드로이드 · 테스트).
  final WidgetBridge? widgets;
  final DateTime Function() _clock;

  /// 테스트에서는 끈다 (타이머가 남으면 테스트가 끝나지 않는다).
  final bool autoRefresh;

  static const _rulesKey = 'ink_rules_v1';
  static const _blockKey = 'ink_blocked_v1';
  static const _themeKey = 'ink_theme_v1';

  /// 화면 모드: auto (아이폰 설정 따라감) · dark · light
  static const themeModes = ['auto', 'dark', 'light'];
  static const _refreshEvery = Duration(seconds: 30);

  SharedPreferences? _prefs;
  Timer? _refreshTimer;
  Timer? _tickTimer;

  Board? board;
  DateTime? _boardAt;
  Hall hall = Hall.empty;
  List<Entry> mine = const [];

  bool loading = false;

  /// 화면 아래 한 줄 알림. (종류, 문장)
  (String, String)? notice;

  /// 마지막으로 실패한 이유 (게시판을 아예 못 불러왔을 때).
  InkError? loadError;

  bool agreed = false;
  final Set<String> blocked = {};

  /// 펼쳐 본 글
  final Set<int> expanded = {};

  Brightness _systemBrightness = Brightness.dark;
  set systemBrightness(Brightness b) {
    if (b == _systemBrightness) return;
    _systemBrightness = b;
    _applyBrightness();
  }

  /// auto · dark · light
  String themeMode = 'auto';

  bool get isLight => themeMode == 'light' || (themeMode == 'auto' && _systemBrightness == Brightness.light);

  void _applyBrightness() {
    brightness.value = isLight ? Brightness.light : Brightness.dark;
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    if (!themeModes.contains(mode) || mode == themeMode) return;
    themeMode = mode;
    await _prefs?.setString(_themeKey, mode);
    _applyBrightness();
    await widgets?.setThemeMode(mode);
  }

  /// 앱 전체 테마만 다시 그리면 되는 변화 (1초마다 도는 시계와 분리).
  final ValueNotifier<Brightness> brightness = ValueNotifier(Brightness.dark);

  TermPalette get palette => TermPalette.of('cmd', light: isLight);

  DateTime now() => _clock();

  /// 다음 글감까지 남은 초 (받아온 뒤 흐른 시간만큼 뺀다).
  int get secondsLeft {
    final b = board;
    if (b == null || _boardAt == null) return 0;
    final passed = _clock().difference(_boardAt!).inSeconds;
    return (b.secondsLeft - passed).clamp(0, 1 << 30);
  }

  /// 규칙 동의 · 차단 목록을 읽는다 (첫 화면을 고르기 전에).
  Future<void> loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    agreed = _prefs!.getBool(_rulesKey) ?? false;
    blocked.addAll(_prefs!.getStringList(_blockKey) ?? const []);
    final mode = _prefs!.getString(_themeKey);
    if (mode != null && themeModes.contains(mode)) themeMode = mode;
    brightness.value = isLight ? Brightness.light : Brightness.dark;
    // 위젯도 같은 모드로 (예전에 고른 값이 위젯에 아직 없을 수 있다).
    final w = widgets;
    if (w != null) unawaited(w.setThemeMode(themeMode));
  }

  Future<void> init() async {
    if (_prefs == null) await loadPrefs();
    notifyListeners();
    await start();
  }

  /// 게시판을 불러오고, 30초마다 새로 고친다.
  Future<void> start() async {
    await refresh();
    if (autoRefresh && _refreshTimer == null) {
      _refreshTimer = Timer.periodic(_refreshEvery, (_) => refresh(quiet: true));
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  void _tick() {
    if (board == null) return;
    if (secondsLeft == 0) {
      refresh(quiet: true);
    } else {
      notifyListeners();
    }
  }

  Future<void> agree() async {
    agreed = true;
    await _prefs?.setBool(_rulesKey, true);
    notifyListeners();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (loading) return;
    loading = true;
    if (!quiet) notifyListeners();
    try {
      await api.ensureSignedIn();
      final b = await api.board();
      final newDay = board != null && board!.day != b.day;
      board = b;
      _boardAt = _clock();
      loadError = null;
      if (newDay) {
        expanded.clear();
        notice = ('info', '새 글감이 열렸어요: ${b.topic}');
      }
    } on InkError catch (e) {
      loadError = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 글 올리기. 성공하면 null, 실패하면 이유.
  Future<InkError?> submit(String body, {EntryKind kind = EntryKind.original, String? title, String? author}) async {
    try {
      await api.ensureSignedIn();
      final r = await api.post(body, kind: kind, title: title, author: author);
      notice = ('ok', '#${two(r.slot)} 자리에 올렸어요. 남은 자리 ${r.cap - r.count}');
      await refresh(quiet: true);
      final w = widgets;
      if (w != null) unawaited(w.reload());
      return null;
    } on InkError catch (e) {
      if (e.code == 'full' || e.code == 'already' || e.code == 'banned') await refresh(quiet: true);
      return e;
    }
  }

  Future<void> toggleLike(Entry e) async {
    if (e.mine || e.deleted || e.hidden) return;
    // 먼저 화면을 바꾸고, 서버 답을 받으면 맞춘다.
    _replace(e.copyWith(liked: !e.liked, likes: e.likes + (e.liked ? -1 : 1)));
    try {
      final r = await api.like(e.id);
      _replace(e.copyWith(liked: r.liked, likes: r.likes));
    } on InkError catch (err) {
      _replace(e);
      notice = ('err', err.message);
      notifyListeners();
    }
  }

  void _replace(Entry e) {
    final b = board;
    if (b == null) return;
    board = b.copyWith(entries: [for (final x in b.entries) x.id == e.id ? e : x]);
    notifyListeners();
  }

  Future<void> report(Entry e, String reason) async {
    try {
      final hidden = await api.report(e.id, reason);
      notice = ('ok', hidden ? '신고했어요. 이 글은 가려졌어요.' : '신고했어요. 3번 쌓이면 바로 가려져요.');
      await refresh(quiet: true);
    } on InkError catch (err) {
      notice = ('err', err.message);
      notifyListeners();
    }
  }

  Future<void> block(Entry e) async {
    blocked.add(e.author);
    await _prefs?.setStringList(_blockKey, blocked.toList());
    notice = ('ok', '${e.nick} 의 글은 이제 안 보여요.');
    notifyListeners();
  }

  Future<void> unblockAll() async {
    blocked.clear();
    await _prefs?.setStringList(_blockKey, const []);
    notice = ('ok', '차단을 모두 풀었어요.');
    notifyListeners();
  }

  Future<void> deleteMine(Entry e) async {
    try {
      await api.deleteMine(e.id);
      notice = ('ok', '내 글을 지웠어요. 자리는 그대로 찬 채로 남아요.');
      await refresh(quiet: true);
      if (mine.isNotEmpty) await loadMine();
    } on InkError catch (err) {
      notice = ('err', err.message);
      notifyListeners();
    }
  }

  void toggleExpanded(Entry e) {
    if (!expanded.remove(e.id)) expanded.add(e.id);
    notifyListeners();
  }

  Future<InkError?> loadHall() async {
    try {
      await api.ensureSignedIn();
      hall = await api.hall();
      notifyListeners();
      return null;
    } on InkError catch (e) {
      return e;
    }
  }

  Future<InkError?> loadMine() async {
    try {
      await api.ensureSignedIn();
      mine = await api.mine();
      notifyListeners();
      return null;
    } on InkError catch (e) {
      return e;
    }
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  // ─────────────── 펜네임 ───────────────

  PenStatus pen = PenStatus.none;

  /// 결제 창구에 연결됐고 상품을 불러왔는지.
  bool shopReady = false;

  /// 결제 · 복원 · 확인 중
  bool penBusy = false;

  /// 펜네임 칸 아래 한 줄 (종류, 문장)
  (String, String)? penNotice;

  StreamSubscription<ShopEvent>? _shopSub;
  Timer? _restoreTimer;

  String? get penPrice => shop?.price;

  /// 결제 창구에 연결하고 내 펜네임을 불러온다. 앱 시작 때 한 번.
  Future<void> initPen() async {
    final s = shop;
    if (s == null) return;
    _shopSub ??= s.events.listen(_onShop);
    shopReady = await s.connect();
    notifyListeners();
    await loadPen();
  }

  Future<void> loadPen() async {
    if (shop == null) return;
    try {
      await api.ensureSignedIn();
      pen = await api.myPen();
      notifyListeners();
    } on InkError {
      // 조용히 넘어간다. 화면을 열 때 다시 부른다.
    }
  }

  void _penSay(String kind, String text, {bool busy = false}) {
    penNotice = (kind, text);
    penBusy = busy;
    notifyListeners();
  }

  Future<void> buyPen() async {
    final s = shop;
    if (s == null || penBusy || pen.owned) return;
    _penSay('info', '결제 창을 여는 중...', busy: true);
    try {
      await s.buy();
    } catch (e) {
      _penSay('err', '스토어에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> restorePen() async {
    final s = shop;
    if (s == null || penBusy) return;
    _penSay('info', '구매 내역을 확인하는 중...', busy: true);
    try {
      await s.restore();
    } catch (e) {
      _penSay('err', '스토어에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }
    // 복원할 내역이 없으면 아무 소식도 오지 않는다.
    _restoreTimer?.cancel();
    _restoreTimer = Timer(const Duration(seconds: 10), () {
      if (penBusy && !pen.owned) _penSay('info', '복원할 구매 내역을 찾지 못했어요.');
    });
  }

  Future<void> _onShop(ShopEvent e) async {
    switch (e.status) {
      case ShopStatus.pending:
        _penSay('info', '결제 승인을 기다리는 중...', busy: true);
      case ShopStatus.canceled:
        _penSay('info', '결제를 취소했어요.');
      case ShopStatus.error:
        _penSay('err', '결제에 실패했어요. ${e.error ?? ''}'.trim());
      case ShopStatus.done:
        _restoreTimer?.cancel();
        _penSay('info', '결제를 확인하는 중...', busy: true);
        try {
          await api.ensureSignedIn();
          pen = await api.claimPen(e.receipt ?? '');
          await shop?.finish(e);
          _penSay(
            'ok',
            pen.name != null
                ? (e.restored ? '구매를 복원했어요. 펜네임: ${pen.name}' : '펜네임: ${pen.name}')
                : (e.restored ? '구매를 복원했어요. 펜네임을 정해 주세요.' : '결제 완료. 펜네임을 정해 주세요.'),
          );
        } on InkError catch (err) {
          // 마무리하지 않았으니 앱을 다시 켜면 자동으로 다시 확인한다.
          _penSay('err', err.message);
        }
    }
  }

  /// 펜네임 정하기 · 바꾸기. 성공하면 null.
  Future<InkError?> setPen(String name) async {
    try {
      await api.ensureSignedIn();
      pen = await api.setPen(name);
      penNotice = ('ok', '펜네임을 ${pen.name}(으)로 정했어요. 오늘부터 올리는 글에 붙어요.');
      notifyListeners();
      return null;
    } on InkError catch (e) {
      return e;
    }
  }

  @override
  void dispose() {
    _shopSub?.cancel();
    _restoreTimer?.cancel();
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    brightness.dispose();
    super.dispose();
  }
}
