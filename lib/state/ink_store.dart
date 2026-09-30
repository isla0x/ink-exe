import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Brightness;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ink_api.dart';
import '../data/models.dart';
import '../theme/term_palette.dart';

/// 앱 상태: 게시판을 불러오고, 글 · +1 · 신고 · 차단을 처리한다.
class InkStore extends ChangeNotifier {
  InkStore({required this.api, DateTime Function()? clock, this.autoRefresh = true})
      : _clock = clock ?? DateTime.now;

  final InkApi api;
  final DateTime Function() _clock;

  /// 테스트에서는 끈다 (타이머가 남으면 테스트가 끝나지 않는다).
  final bool autoRefresh;

  static const _rulesKey = 'ink_rules_v1';
  static const _blockKey = 'ink_blocked_v1';
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
    brightness.value = b;
    notifyListeners();
  }

  /// 앱 전체 테마만 다시 그리면 되는 변화 (1초마다 도는 시계와 분리).
  final ValueNotifier<Brightness> brightness = ValueNotifier(Brightness.dark);

  TermPalette get palette => TermPalette.of('cmd', light: _systemBrightness == Brightness.light);

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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tickTimer?.cancel();
    brightness.dispose();
    super.dispose();
  }
}
