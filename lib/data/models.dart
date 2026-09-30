/// 서버에서 받은 데이터 모양. JSON 키는 supabase/schema.sql 의 함수 결과와 같다.
library;

String two(int n) => n.toString().padLeft(2, '0');

const weekdayKo = ['월', '화', '수', '목', '금', '토', '일'];

/// `09.30 수`
String shortDate(DateTime d) => '${two(d.month)}.${two(d.day)} ${weekdayKo[d.weekday - 1]}';

/// `2026.09.30`
String dotDate(DateTime d) => '${d.year}.${two(d.month)}.${two(d.day)}';

/// 01:02:03
String hms(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
}

DateTime _day(Object? v) => DateTime.parse(v as String);

enum EntryKind { original, quote }

class Entry {
  const Entry({
    required this.id,
    required this.day,
    required this.slot,
    required this.nick,
    this.pen = false,
    required this.author,
    required this.kind,
    required this.body,
    this.srcTitle,
    this.srcAuthor,
    required this.likes,
    required this.liked,
    required this.mine,
    required this.hidden,
    required this.deleted,
    required this.time,
    this.topic,
    this.month,
  });

  final int id;
  final DateTime day;
  final int slot;

  /// 그날의 익명 이름 guest_0000, 또는 글을 올릴 때의 펜네임
  final String nick;

  /// [nick] 이 펜네임이면 true
  final bool pen;

  /// 차단용 작성자 표시 (날이 바뀌어도 같다)
  final String author;
  final EntryKind kind;

  /// 가려졌거나 지워졌으면 null
  final String? body;
  final String? srcTitle;
  final String? srcAuthor;
  final int likes;
  final bool liked;
  final bool mine;
  final bool hidden;
  final bool deleted;

  /// `09:41`
  final String time;

  /// 명예의 전당 · 내 글에서만
  final String? topic;
  final String? month;

  bool get isQuote => kind == EntryKind.quote;

  /// `— 『데미안』, 헤르만 헤세`
  String? get source => isQuote && srcTitle != null ? '— 『$srcTitle』, ${srcAuthor ?? ''}'.trimRight() : null;

  String get slotLabel => '#${two(slot)}';

  Entry copyWith({int? likes, bool? liked, bool? deleted, String? body}) => Entry(
        id: id,
        day: day,
        slot: slot,
        nick: nick,
        pen: pen,
        author: author,
        kind: kind,
        body: deleted == true ? null : (body ?? this.body),
        srcTitle: deleted == true ? null : srcTitle,
        srcAuthor: deleted == true ? null : srcAuthor,
        likes: likes ?? this.likes,
        liked: liked ?? this.liked,
        mine: mine,
        hidden: hidden,
        deleted: deleted ?? this.deleted,
        time: time,
        topic: topic,
        month: month,
      );

  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
        id: (j['id'] as num).toInt(),
        day: _day(j['day']),
        slot: (j['slot'] as num).toInt(),
        nick: (j['nick'] as String?) ?? '',
        pen: (j['pen'] as bool?) ?? false,
        author: (j['author'] as String?) ?? '',
        kind: j['kind'] == 'quote' ? EntryKind.quote : EntryKind.original,
        body: j['body'] as String?,
        srcTitle: j['src_title'] as String?,
        srcAuthor: j['src_author'] as String?,
        likes: (j['likes'] as num?)?.toInt() ?? 0,
        liked: (j['liked'] as bool?) ?? false,
        mine: (j['mine'] as bool?) ?? false,
        hidden: (j['hidden'] as bool?) ?? false,
        deleted: (j['deleted'] as bool?) ?? false,
        time: (j['time'] as String?) ?? '',
        topic: j['topic'] as String?,
        month: j['month'] as String?,
      );
}

class Board {
  const Board({
    required this.day,
    required this.isToday,
    required this.topic,
    required this.cap,
    required this.maxLen,
    required this.count,
    required this.mineSlot,
    required this.banned,
    required this.secondsLeft,
    required this.entries,
  });

  final DateTime day;
  final bool isToday;

  /// 오늘의 글감
  final String topic;
  final int cap;
  final int maxLen;
  final int count;

  /// 오늘 내 자리. 아직 안 썼으면 null
  final int? mineSlot;
  final bool banned;

  /// 다음 글감까지 남은 초 (받아온 순간 기준)
  final int secondsLeft;
  final List<Entry> entries;

  int get left => (cap - count).clamp(0, cap);
  bool get full => count >= cap;
  bool get posted => mineSlot != null;
  bool get canWrite => isToday && !posted && !full && !banned;

  Board copyWith({List<Entry>? entries, int? count, int? mineSlot}) => Board(
        day: day,
        isToday: isToday,
        topic: topic,
        cap: cap,
        maxLen: maxLen,
        count: count ?? this.count,
        mineSlot: mineSlot ?? this.mineSlot,
        banned: banned,
        secondsLeft: secondsLeft,
        entries: entries ?? this.entries,
      );

  factory Board.fromJson(Map<String, dynamic> j) => Board(
        day: _day(j['day']),
        isToday: (j['is_today'] as bool?) ?? true,
        topic: (j['topic'] as String?) ?? '',
        cap: (j['cap'] as num?)?.toInt() ?? 20,
        maxLen: (j['max_len'] as num?)?.toInt() ?? 300,
        count: (j['count'] as num?)?.toInt() ?? 0,
        mineSlot: (j['mine_slot'] as num?)?.toInt(),
        banned: (j['banned'] as bool?) ?? false,
        secondsLeft: (j['seconds_left'] as num?)?.toInt() ?? 0,
        entries: [
          for (final e in (j['posts'] as List? ?? const [])) Entry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

class Hall {
  const Hall({required this.monthLabel, required this.today, required this.month, required this.champions});

  /// `2026.10`
  final String monthLabel;

  /// 오늘 지금 1위 (아직 확정 아님)
  final Entry? today;

  /// 이번 달 날마다 1위 (최근 날부터)
  final List<Entry> month;

  /// 지난달들의 이달의 1위 (최근 달부터)
  final List<Entry> champions;

  static const empty = Hall(monthLabel: '', today: null, month: [], champions: []);

  factory Hall.fromJson(Map<String, dynamic> j) {
    List<Entry> list(Object? v) => [
          for (final e in (v as List? ?? const [])) Entry.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
    final t = j['today'];
    return Hall(
      monthLabel: (j['month_label'] as String?) ?? '',
      today: t == null ? null : Entry.fromJson(Map<String, dynamic>.from(t as Map)),
      month: list(j['month']),
      champions: list(j['champions']),
    );
  }
}

class PostResult {
  const PostResult(this.slot, this.count, this.cap);

  final int slot;
  final int count;
  final int cap;
}

class LikeResult {
  const LikeResult(this.likes, this.liked);

  final int likes;
  final bool liked;
}

/// 펜네임 (유료, 한 번 구매).
class PenStatus {
  const PenStatus({required this.owned, this.name, this.nextChange});

  static const none = PenStatus(owned: false);

  /// 샀는지
  final bool owned;

  /// 정한 이름. 샀지만 아직 안 정했으면 null.
  final String? name;

  /// 이 시각 전에는 바꿀 수 없다. null 이면 지금 바꿀 수 있다.
  final DateTime? nextChange;

  factory PenStatus.fromJson(Map<String, dynamic> j) => PenStatus(
        owned: (j['owned'] as bool?) ?? false,
        name: j['name'] as String?,
        nextChange: j['next_change'] == null ? null : DateTime.parse(j['next_change'] as String).toLocal(),
      );
}

/// 서버가 거절한 이유. 서버는 `ink:<코드>` 로 알려준다.
class InkError implements Exception {
  const InkError(this.code, [this.detail]);

  final String code;
  final String? detail;

  static InkError fromMessage(String message) {
    final m = RegExp(r'ink:([a-z_]+)').firstMatch(message);
    return InkError(m?.group(1) ?? 'network', message);
  }

  /// 사용자에게 보여줄 문장.
  String get message => switch (code) {
        'full' => 'Server is full. 오늘 자리가 모두 찼어요.',
        'already' => '오늘은 이미 한 편 올렸어요.',
        'empty' => '빈 글은 올릴 수 없어요.',
        'too_long' => '글자 수를 넘었어요.',
        'link' => '링크나 주소는 올릴 수 없어요.',
        'word' => '쓸 수 없는 단어가 들어 있어요.',
        'source' => '인용이면 작품명과 작가를 적어 주세요.',
        'banned' => '규칙 위반으로 쓰기가 제한된 기기예요.',
        'own' => '내 글에는 할 수 없어요.',
        'not_found' => '글을 찾을 수 없어요.',
        'auth' => '서버에 접속하지 못했어요. 잠시 후 다시 시도해 주세요.',
        'device' => '이 기기를 확인하지 못했어요. 인터넷을 확인하고 앱을 다시 열어 주세요.',
        'no_pen' => '펜네임을 먼저 구매해 주세요.',
        'pen_len' => '펜네임은 2~12자로 정해 주세요.',
        'pen_chars' => '한글 · 영문 · 숫자 · _ 만 쓸 수 있어요. (띄어쓰기 불가, 숫자는 6개까지)',
        'pen_reserved' => 'guest · 운영자처럼 헷갈리는 이름은 쓸 수 없어요.',
        'pen_taken' => '이미 누가 쓰고 있는 펜네임이에요.',
        'pen_wait' => '펜네임은 7일에 한 번 바꿀 수 있어요.',
        'pen_receipt' => '결제를 확인하지 못했어요. 잠시 후 [구매 복원]을 눌러 주세요.',
        _ => '서버에 연결하지 못했어요. 인터넷을 확인해 주세요.',
      };

  @override
  String toString() => 'InkError($code, $detail)';
}

/// 신고 이유 (서버에는 key 로 저장).
const reportReasons = <(String, String)>[
  ('abuse', '욕설 · 비방 · 혐오'),
  ('privacy', '개인정보가 들어 있어요'),
  ('spam', '광고 · 도배'),
  ('copyright', '저작권 문제 (출처 없는 인용 등)'),
  ('etc', '그 밖의 규칙 위반'),
];
