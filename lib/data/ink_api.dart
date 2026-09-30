import 'models.dart';

/// 서버와 주고받는 일. 실제는 [SupabaseInkApi], 테스트 · 서버 없는 데모는 [DemoInkApi].
abstract class InkApi {
  /// 익명 로그인. 이미 되어 있으면 아무것도 안 한다.
  Future<void> ensureSignedIn();

  /// [day] 가 null 이면 오늘.
  Future<Board> board({DateTime? day});

  Future<PostResult> post(String body, {EntryKind kind = EntryKind.original, String? title, String? author});

  Future<LikeResult> like(int id);

  /// 가려졌으면 true.
  Future<bool> report(int id, String reason);

  Future<void> deleteMine(int id);

  Future<Hall> hall();

  Future<List<Entry>> mine();

  /// 내 펜네임 상태.
  Future<PenStatus> myPen();

  /// 펜네임 정하기 · 바꾸기.
  Future<PenStatus> setPen(String name);

  /// Apple 결제 영수증(JWS)을 서버에서 확인하고 펜네임 권한을 받는다. 구매 · 복원 둘 다.
  Future<PenStatus> claimPen(String receipt);
}
