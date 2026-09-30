import 'ink_api.dart';
import 'models.dart';

/// 서버 없이 도는 가짜 서버. 테스트와 '서버 설정 전' 데모 실행에 쓴다.
/// 규칙은 supabase/schema.sql 과 같게 맞춘다 (선착순, 글자 수, 하루 한 편, 신고 3번).
class DemoInkApi implements InkApi {
  DemoInkApi({DateTime Function()? clock, this.cap = 20, this.maxLen = 300, bool seed = false})
      : _clock = clock ?? DateTime.now {
    if (seed) _seed();
  }

  final DateTime Function() _clock;
  final int cap;
  final int maxLen;

  static const me = 'me';
  static final epoch = DateTime(2026, 10, 1);

  static const topicPool = [
    '파란 나무', '마지막 버스', '잠긴 서랍', '비 오는 옥상', '오래된 편지',
    '고양이의 비밀', '새벽 네 시', '잃어버린 우산', '빈 놀이터', '거울 속의 나',
    '첫눈', '낡은 카메라', '여름의 끝', '이름 없는 섬', '종이비행기',
    '붉은 달', '두 번째 기회', '창문 너머', '사라진 기차역', '오늘의 거짓말',
    '소금 맛 바람', '유리 정원', '열쇠 하나', '기억 상점', '밤의 도서관',
    '초록 우체통', '시간을 파는 가게', '무지개 계단', '모래시계', '이상한 초대장',
    '달리는 꿈', '겨울 바다', '노란 우산', '녹슨 자전거', '별이 떨어진 날',
    '비밀 지도', '마지막 한 조각', '잠들지 않는 도시', '오래된 약속', '하얀 거짓말',
    '구름 공장', '투명 인간', '늦은 답장', '이사 가는 날', '빈 의자',
    '목소리 없는 노래', '푸른 새벽', '등대지기', '반쪽짜리 편지', '미로',
    '첫 월급', '버려진 인형', '여우비', '뒤바뀐 이름', '불 꺼진 무대',
    '기차 창밖', '작은 용', '낯선 전화', '시계탑', '은하수 식당',
  ];

  static const _banned = ['시발', '씨발', 'ㅅㅂ', '병신', 'ㅂㅅ', '좆', '개새끼', '닥쳐', '꺼져', '섹스', '자살하', '죽어라', '카톡아이디', '오픈채팅', '텔레그램'];
  static final _link = RegExp(r'(https?://|www\.|[a-z0-9-]+\.(com|net|org|kr|io|me|co|ly|gg|link)(/|\s|$))', caseSensitive: false);

  final List<_Post> _posts = [];
  final Set<String> bannedUsers = {};
  String user = me;
  int _nextId = 1;

  DateTime get _today {
    final n = _clock();
    return DateTime(n.year, n.month, n.day);
  }

  static String topicFor(DateTime d) {
    final diff = DateTime(d.year, d.month, d.day).difference(epoch).inDays;
    final i = ((diff % topicPool.length) + topicPool.length) % topicPool.length;
    return topicPool[i];
  }


  String nickOf(String u, DateTime d) {
    final n = ((u.hashCode ^ (d.day * 7919) ^ (d.month * 104729)) & 0x7fffffff) % 10000;
    return 'guest_${n.toString().padLeft(4, '0')}';
  }

  Entry _entry(_P p, {bool withTopic = false, String? month}) {
    final viewer = user;
    final masked = p.deleted || (p.hidden && p.user != viewer);
    return Entry(
      id: p.id,
      day: p.day,
      slot: p.slot,
      nick: p.pen ?? nickOf(p.user, p.day),
      pen: p.pen != null,
      author: 'a${p.user.hashCode & 0xffffff}',
      kind: p.kind,
      body: masked ? null : p.body,
      srcTitle: masked ? null : p.title,
      srcAuthor: masked ? null : p.author,
      likes: p.likers.length,
      liked: p.likers.contains(viewer),
      mine: p.user == viewer,
      hidden: p.hidden,
      deleted: p.deleted,
      time: '${two(p.created.hour)}:${two(p.created.minute)}',
      topic: withTopic ? topicFor(p.day) : null,
      month: month,
    );
  }

  @override
  Future<void> ensureSignedIn() async {}

  int get _secondsLeft {
    final n = _clock();
    return DateTime(n.year, n.month, n.day + 1).difference(n).inSeconds;
  }

  @override
  Future<Board> board({DateTime? day}) async {
    final today = _today;
    var d = day == null ? today : DateTime(day.year, day.month, day.day);
    if (d.isAfter(today)) d = today;
    final list = _posts.where((p) => p.day == d).toList()..sort((a, b) => a.slot.compareTo(b.slot));
    final mine = list.where((p) => p.user == user);
    return Board(
      day: d,
      isToday: d == today,
      topic: topicFor(d),
      cap: cap,
      maxLen: maxLen,
      count: list.length,
      mineSlot: mine.isEmpty ? null : mine.first.slot,
      banned: bannedUsers.contains(user),
      secondsLeft: _secondsLeft,
      entries: [for (final p in list) _entry(p)],
    );
  }

  @override
  Future<PostResult> post(String body, {EntryKind kind = EntryKind.original, String? title, String? author}) async {
    if (bannedUsers.contains(user)) throw const InkError('banned');
    var b = body.replaceAll(RegExp(r'\r\n?'), '\n').replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    b = b.trim();
    if (b.isEmpty) throw const InkError('empty');
    if (b.runes.length > maxLen) throw const InkError('too_long');
    var t = title?.trim();
    var a = author?.trim();
    if (kind == EntryKind.quote) {
      if (t == null || t.isEmpty || a == null || a.isEmpty || t.runes.length > 60 || a.runes.length > 40) {
        throw const InkError('source');
      }
    } else {
      t = null;
      a = null;
    }
    final all = '$b ${t ?? ''} ${a ?? ''}';
    if (_link.hasMatch(all)) throw const InkError('link');
    final squeezed = all.replaceAll(RegExp(r'\s'), '').toLowerCase();
    if (_banned.any(squeezed.contains)) throw const InkError('word');
    final d = _today;
    final today = _posts.where((p) => p.day == d).toList();
    if (today.any((p) => p.user == user)) throw const InkError('already');
    if (today.length >= cap) throw const InkError('full');
    final slot = today.length + 1;
    _posts.add(_P(_nextId++, d, slot, user, kind, b, t, a, _clock())..pen = _pens[user]?.name);
    return PostResult(slot, slot, cap);
  }

  _P _find(int id) => _posts.firstWhere((p) => p.id == id, orElse: () => throw const InkError('not_found'));

  @override
  Future<LikeResult> like(int id) async {
    final p = _find(id);
    if (p.deleted || p.hidden) throw const InkError('not_found');
    if (p.user == user) throw const InkError('own');
    final liked = !p.likers.remove(user);
    if (liked) p.likers.add(user);
    return LikeResult(p.likers.length, liked);
  }

  @override
  Future<bool> report(int id, String reason) async {
    final p = _find(id);
    if (p.user == user) throw const InkError('own');
    p.reporters.add(user);
    if (p.reporters.length >= 3) p.hidden = true;
    return p.hidden;
  }

  @override
  Future<void> deleteMine(int id) async {
    final p = _find(id);
    if (p.user != user) throw const InkError('not_found');
    p.deleted = true;
    p.body = null;
    p.title = null;
    p.author = null;
    p.likers.clear();
  }

  bool _eligible(_P p) => !p.hidden && !p.deleted && p.likers.isNotEmpty;

  _P? _top(Iterable<_P> ps) {
    final list = ps.where(_eligible).toList()
      ..sort((a, b) {
        final byLikes = b.likers.length.compareTo(a.likers.length);
        if (byLikes != 0) return byLikes;
        final byDay = a.day.compareTo(b.day);
        return byDay != 0 ? byDay : a.slot.compareTo(b.slot);
      });
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<Hall> hall() async {
    final today = _today;
    final monthStart = DateTime(today.year, today.month);
    final days = _posts.map((p) => p.day).where((d) => !d.isBefore(monthStart) && d.isBefore(today)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final month = <Entry>[
      for (final d in days)
        if (_top(_posts.where((p) => p.day == d)) case final p?) _entry(p, withTopic: true),
    ];
    final months = _posts.map((p) => DateTime(p.day.year, p.day.month)).where((m) => m.isBefore(monthStart)).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final champions = <Entry>[
      for (final m in months)
        if (_top(_posts.where((p) => p.day.year == m.year && p.day.month == m.month)) case final p?)
          _entry(p, withTopic: true, month: '${m.year}.${two(m.month)}'),
    ];
    final t = _top(_posts.where((p) => p.day == today));
    return Hall(
      monthLabel: '${today.year}.${two(today.month)}',
      today: t == null ? null : _entry(t, withTopic: true),
      month: month,
      champions: champions,
    );
  }

  @override
  Future<List<Entry>> mine() async {
    final list = _posts.where((p) => p.user == user).toList()..sort((a, b) => b.day.compareTo(a.day));
    return [for (final p in list) _entry(p, withTopic: true)];
  }

  // ── 펜네임 (schema.sql 의 set_pen 과 같은 규칙) ──

  final Map<String, _Pen> _pens = {};

  /// 이 영수증 문자열이면 결제 확인에 실패한 것으로 친다 (테스트용).
  static const badReceipt = 'bad';

  PenStatus _penOf(String u) {
    final r = _pens[u];
    if (r == null) return PenStatus.none;
    final next = r.changedAt?.add(const Duration(days: 7));
    return PenStatus(owned: true, name: r.name, nextChange: next != null && next.isAfter(_clock()) ? next : null);
  }

  @override
  Future<PenStatus> myPen() async => _penOf(user);

  @override
  Future<PenStatus> claimPen(String receipt) async {
    if (receipt.isEmpty || receipt == badReceipt) throw const InkError('pen_receipt');
    // 같은 영수증이 다른 사용자로 오면 옮긴다 (구매 복원).
    String? owner;
    for (final e in _pens.entries) {
      if (e.value.receipt == receipt) owner = e.key;
    }
    if (owner != null && owner != user && !_pens.containsKey(user)) {
      _pens[user] = _pens.remove(owner)!;
    } else {
      _pens.putIfAbsent(user, () => _Pen(receipt));
    }
    return _penOf(user);
  }

  @override
  Future<PenStatus> setPen(String name) async {
    final r = _pens[user];
    if (r == null) throw const InkError('no_pen');
    if (bannedUsers.contains(user)) throw const InkError('banned');
    final n = name.trim();
    if (n.runes.length < 2 || n.runes.length > 12) throw const InkError('pen_len');
    if (!RegExp(r'^[가-힣A-Za-z0-9_]+$').hasMatch(n) || n.replaceAll(RegExp(r'[^0-9]'), '').length > 6) {
      throw const InkError('pen_chars');
    }
    if (RegExp(r'^(guest|admin|ink)', caseSensitive: false).hasMatch(n) || RegExp('(운영|관리자|공식)').hasMatch(n)) {
      throw const InkError('pen_reserved');
    }
    if (_banned.any(n.toLowerCase().contains)) throw const InkError('word');
    if (r.name == n) return _penOf(user);
    if (_penOf(user).nextChange != null) throw const InkError('pen_wait');
    if (_pens.entries.any((e) => e.key != user && e.value.name?.toLowerCase() == n.toLowerCase())) {
      throw const InkError('pen_taken');
    }
    r
      ..name = n
      ..changedAt = _clock();
    return _penOf(user);
  }

  /// 테스트용: 다른 사람에게 펜네임을 준다.
  void givePen(String who, String name) => _pens[who] = _Pen('gift-$who')..name = name;

  /// 테스트용: 다른 사람으로 글 쓰기.
  Future<PostResult> postAs(String who, String body, {EntryKind kind = EntryKind.original, String? title, String? author}) async {
    final prev = user;
    user = who;
    try {
      return await post(body, kind: kind, title: title, author: author);
    } finally {
      user = prev;
    }
  }

  /// 테스트용: 다른 사람으로 +1 / 신고.
  Future<void> likeAs(String who, int id) async {
    final prev = user;
    user = who;
    try {
      await like(id);
    } finally {
      user = prev;
    }
  }

  Future<void> reportAs(String who, int id) async {
    final prev = user;
    user = who;
    try {
      await report(id, 'abuse');
    } finally {
      user = prev;
    }
  }

  int idOfSlot(int slot, {DateTime? day}) {
    final d = day ?? _today;
    return _posts.firstWhere((p) => p.day == d && p.slot == slot).id;
  }

  void _seed() {
    final d = _today;
    const lines = [
      ('파란 잎이 떨어질 때마다 할머니는 그 잎에 이름을 붙였다. 오늘은 내 차례였다.', null, null),
      ('나무는 원래 초록이 아니었다고, 아무도 믿지 않는 이야기를 아버지는 매년 봄마다 했다.', null, null),
      ('새는 알에서 나오려고 투쟁한다. 알은 세계이다. 태어나려는 자는 하나의 세계를 깨뜨려야 한다.', '데미안', '헤르만 헤세'),
      ('그 나무 아래서 우리는 처음으로 서로의 진짜 이름을 불렀다.', null, null),
      ('밤새 비가 오고 나면 골목 끝 나무가 조금 더 파래져 있었다.', null, null),
      ('파란 나무는 슬플 때만 보인다고 했다. 그날 나는 숲 전체가 파랗게 보였다.', null, null),
      ('편의점 앞 가로수에 누가 파란 페인트를 칠해 놓았다. 경찰은 범인을 찾지 못했고, 나는 찾고 싶지 않았다.', null, null),
      ('뿌리는 기억을 먹고 자란다. 그래서 오래된 나무일수록 푸르다.', null, null),
      ('나는 그 나무를 그리려고 물감을 샀는데, 파란색만 다 떨어져 있었다.', null, null),
      ('할 말이 많은 날엔 나무에게 먼저 말해 본다. 나무는 한 번도 끊지 않았다.', null, null),
      ('우리 동네에는 사계절 내내 파란 나무가 한 그루 있다. 모두 그 나무를 모른 척한다.', null, null),
    ];
    for (var i = 0; i < lines.length; i++) {
      final (b, t, a) = lines[i];
      _posts.add(_P(
        _nextId++,
        d,
        i + 1,
        'seed$i',
        t == null ? EntryKind.original : EntryKind.quote,
        b,
        t,
        a,
        d.add(Duration(minutes: 1 + i * 37)),
      )..likers.addAll([for (var k = 0; k < (13 - i) % 9; k++) 'fan$k']));
    }
  }
}

typedef _P = _Post;

class _Pen {
  _Pen(this.receipt);

  final String receipt;
  String? name;
  DateTime? changedAt;
}

class _Post {
  _Post(this.id, this.day, this.slot, this.user, this.kind, this.body, this.title, this.author, this.created);

  final int id;
  final DateTime day;
  final int slot;
  final String user;
  final EntryKind kind;
  String? body;
  String? title;
  String? author;
  final DateTime created;
  final Set<String> likers = {};
  final Set<String> reporters = {};
  bool hidden = false;
  bool deleted = false;
  String? pen;
}
