import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ink_exe/data/demo_api.dart';
import 'package:ink_exe/data/draft.dart';
import 'package:ink_exe/state/ink_store.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('private drafts persist without loading or posting to the board', () async {
    SharedPreferences.setMockInitialValues({});
    final s = InkStore(api: DemoInkApi(), autoRefresh: false);
    await s.loadPrefs();
    await s.saveDraft(Draft(id:'1', day:'2026-10-23', topic:'가을', body:'비공개 글', updated:DateTime(2026,10,23)));
    expect(s.board, isNull);
    final next = InkStore(api: DemoInkApi(), autoRefresh: false);
    await next.loadPrefs();
    expect(next.drafts.single.body, '비공개 글');
    await next.deleteDraft('1');
    final third = InkStore(api: DemoInkApi(), autoRefresh: false);
    await third.loadPrefs();
    expect(third.drafts, isEmpty);
    s.dispose(); next.dispose(); third.dispose();
  });
}
