import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/entry_card.dart';
import '../widgets/term_widgets.dart';
import 'nav_tabs.dart';
import 'write_screen.dart';

/// 메인: 오늘의 글감 + 선착순 20편 + 쓰기.
class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key, required this.store});

  final InkStore store;

  Future<void> _write(BuildContext context) async {
    await Navigator.of(context).push<bool>(termRoute(WriteScreen(store: store)));
  }

  void _menu(BuildContext context, Entry e) {
    final p = store.palette;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.bar,
      shape: RoundedRectangleBorder(side: BorderSide(color: p.cmd)),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: e.mine ? _mineMenu(sheet, p, e) : _reportMenu(sheet, p, e),
        ),
      ),
    );
  }

  Widget _mineMenu(BuildContext sheet, TermPalette p, Entry e) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('C:\\ink> rm ${e.slotLabel}', style: termStyle(p.dim, size: 13)),
          const SizedBox(height: 8),
          Text('지우면 되돌릴 수 없어요. 자리는 찬 채로 남아요.', style: termStyle(p.fg, size: 13, ko: true)),
          const SizedBox(height: 12),
          TermBoxButton(
            palette: p,
            label: '내 글 지우기',
            textColor: p.warn,
            onTap: () {
              Navigator.of(sheet).pop();
              store.deleteMine(e);
            },
          ),
          const SizedBox(height: 6),
          TermBoxButton(palette: p, label: '[ ESC ] 닫기', onTap: () => Navigator.of(sheet).pop()),
        ],
      );

  Widget _reportMenu(BuildContext sheet, TermPalette p, Entry e) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('C:\\ink> report ${e.slotLabel} · ${e.nick}', style: termStyle(p.dim, size: 13)),
          const SizedBox(height: 8),
          Text('신고하면 이 글은 바로 내 화면에서 사라지고, 운영자가 24시간 안에 확인해 지우고 쓴 사람을 내보내요.',
              style: termStyle(p.fg, size: 12, ko: true)),
          const SizedBox(height: 8),
          Text('신고 이유', style: termStyle(p.hi, size: 13)),
          const SizedBox(height: 6),
          for (final (key, label) in reportReasons)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: TermBoxButton(
                palette: p,
                label: label,
                onTap: () {
                  Navigator.of(sheet).pop();
                  store.report(e, key);
                },
              ),
            ),
          const SizedBox(height: 6),
          TermBoxButton(
            palette: p,
            label: '이 사람 차단하기 (글 바로 숨김)',
            textColor: p.warn,
            onTap: () {
              Navigator.of(sheet).pop();
              store.block(e);
            },
          ),
          const SizedBox(height: 6),
          TermBoxButton(palette: p, label: '[ ESC ] 닫기', onTap: () => Navigator.of(sheet).pop()),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.palette;
        final b = store.board;
        return Scaffold(
          backgroundColor: p.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(
                palette: p,
                now: store.now(),
                tabs: navTabs(context, store),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: p.cmd,
                  backgroundColor: p.bar,
                  onRefresh: store.refresh,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    children: [
                      Text('INK [오늘의 글감]', style: termStyle(p.hi)),
                      Text('익명 · 하루 한 편 · 선착순 ${b?.cap ?? 20}명 · 자정에 새 글감',
                          style: termStyle(p.dim, size: 13, ko: true)),
                      const SizedBox(height: 14),
                      Text.rich(TextSpan(children: [
                        TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                        TextSpan(text: 'topic', style: termStyle(p.cmd)),
                      ])),
                      const SizedBox(height: 2),
                      Semantics(
                        header: true,
                        child: Text(
                          b == null ? '...' : b.topic,
                          style: termStyle(p.hi, size: 26, weight: FontWeight.w700, ko: true, height: 1.3),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (b != null) _status(p, b),
                      const SizedBox(height: 10),
                      DashedDivider(color: p.line),
                      if (b == null && store.loadError != null)
                        _error(p)
                      else if (b == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text('CONNECT ...', style: termStyle(p.dim, size: 13)),
                        )
                      else if (b.entries.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text('아직 아무도 안 썼어요. 첫 자리를 잡아 보세요.', style: termStyle(p.dim, size: 13, ko: true)),
                        )
                      else
                        for (final e in b.entries)
                          EntryCard(
                            key: ValueKey(e.id),
                            entry: e,
                            palette: p,
                            expanded: store.expanded.contains(e.id),
                            blocked: store.blocked.contains(e.author),
                            reported: store.reported.contains(e.id),
                            onTap: () => store.toggleExpanded(e),
                            onLike: () => store.toggleLike(e),
                            onMenu: () => _menu(context, e),
                          ),
                    ],
                  ),
                ),
              ),
              _footer(context, p, b),
            ],
          ),
        );
      },
    );
  }

  Widget _status(TermPalette p, Board b) {
    final cells = b.cap == 0 ? 0 : (b.count * 10 / b.cap).round().clamp(0, 10);
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('접속', style: termStyle(p.dim, size: 13)),
        Text('[${'█' * cells}${'░' * (10 - cells)}]', style: termStyle(b.full ? p.warn : p.cmd, size: 13)),
        Text('${b.count}/${b.cap}', style: termStyle(p.hi, size: 13)),
        Text(b.full ? 'FULL' : '남은 자리 ${b.left}', style: termStyle(b.full ? p.warn : p.dim, size: 13)),
      ],
    );
  }

  Widget _error(TermPalette p) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(store.loadError!.message, style: termStyle(p.warn, size: 13, ko: true)),
            const SizedBox(height: 8),
            TermBoxButton(palette: p, label: '다시 시도', textColor: p.cmd, onTap: store.refresh),
          ],
        ),
      );

  Widget _footer(BuildContext context, TermPalette p, Board? b) {
    final n = store.notice;
    final noticeColor = switch (n?.$1) { 'ok' => p.cmd, 'err' => p.warn, _ => p.dim };
    final clock = hms(store.secondsLeft);

    Widget action;
    if (b == null) {
      action = const SizedBox.shrink();
    } else if (b.banned) {
      action = _line(p, '규칙 위반으로 쓰기가 제한된 기기예요.', p.warn);
    } else if (b.posted) {
      action = _line(p, '✓ 오늘 #${two(b.mineSlot!)} 에 올렸어요 · 다음 글감까지 $clock', p.fg);
    } else if (b.full) {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Server is full.', style: termStyle(p.warn, weight: FontWeight.w700)),
          Text('오늘 ${b.cap}자리가 모두 찼어요. 다음 글감까지 $clock',
              style: termStyle(p.fg, size: 13, ko: true)),
        ],
      );
    } else {
      action = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('내 자리 #${two(b.count + 1)} · 남은 자리 ${b.left} · 마감까지 $clock',
              style: termStyle(p.dim, size: 12, ko: true)),
          const SizedBox(height: 6),
          TermWideButton(palette: p, keyLabel: '[ ENTER ]', label: '쓰기', onTap: () => _write(context)),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(color: p.bar, border: Border(top: BorderSide(color: p.line))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (n != null)
              Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(n.$2, style: termStyle(noticeColor, size: 13, ko: true)),
                ),
              ),
            action,
          ],
        ),
      ),
    );
  }

  Widget _line(TermPalette p, String text, Color color) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: p.bg, border: Border.all(color: p.line)),
        child: Text(text, style: termStyle(color, size: 13, ko: true)),
      );
}
