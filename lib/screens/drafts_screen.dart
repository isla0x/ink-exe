import 'package:flutter/material.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/term_widgets.dart';
import 'write_screen.dart';

class DraftsScreen extends StatelessWidget {
  const DraftsScreen({super.key, required this.store});
  final InkStore store;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) {
    final p = store.palette;
    return Scaffold(backgroundColor: p.bg, body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TitleBar(palette: p, now: store.now(), active: '서랍', tabs: const [('서랍', null)]),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('내 글 서랍', style: termStyle(p.hi, size: 22, ko: true)),
        Text('게시판 자리가 차도 쓸 수 있어요.\n초안은 공개되지 않으며 이 기기에만 저장돼요.', style: termStyle(p.dim, size: 13, ko: true)),
        const SizedBox(height: 12),
        if (store.drafts.isEmpty) Text('아직 저장한 초안이 없어요.', style: termStyle(p.dim)),
        for (final d in store.drafts) ListTile(contentPadding: EdgeInsets.zero,
          title: Text(d.topic, style: termStyle(p.cmd)),
          subtitle: Text('${d.day}\n${d.body}', maxLines: 3, overflow: TextOverflow.ellipsis, style: termStyle(p.fg, size: 13, ko: true)),
          onTap: () => Navigator.of(context).push(termRoute(WriteScreen(store: store, draft: d, privateOnly: true))),
          trailing: IconButton(tooltip: '초안 삭제', icon: Icon(Icons.delete_outline, color: p.dim), onPressed: () async {
            final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
              title: const Text('이 초안을 지울까요?'), actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소')),
                TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('삭제')),
              ]));
            if (yes == true) { try { await store.deleteDraft(d.id); } catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('초안을 지우지 못했어요. 다시 시도해 주세요.'))); } }
          })),
      ])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        TermWideButton(palette: p, keyLabel: '[ NEW ]', label: '새 비공개 초안', onTap: () => Navigator.of(context).push(termRoute(WriteScreen(store: store, privateOnly: true)))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('[ ESC ] 닫기')),
      ]))),
    ]));
  });
}
