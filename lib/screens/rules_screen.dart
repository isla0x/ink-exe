import 'package:flutter/material.dart';

import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/term_widgets.dart';
import 'board_screen.dart';
import 'nav_tabs.dart';

const inkRules = [
  '욕설 · 비방 · 혐오 · 성적인 글 금지',
  '이름 · 연락처 · SNS 계정 등 개인정보 금지',
  '광고 · 링크 · 도배 금지',
  '다른 작품을 옮겨 적을 땐 작품명과 작가를 꼭 적기 (300자 이내)',
  '신고가 3번 쌓인 글은 바로 가려지고, 24시간 안에 확인해 지워요',
  '규칙을 어긴 기기는 쓰기가 막혀요',
];

/// 첫 실행: 규칙 동의. [readOnly] 면 규칙 다시 보기 (+ 차단 풀기).
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, required this.store, this.readOnly = false});

  final InkStore store;
  final bool readOnly;

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  bool _checked = false;

  Future<void> _enter() async {
    await widget.store.agree();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(termRoute(BoardScreen(store: widget.store)));
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.palette;
        return Scaffold(
          backgroundColor: p.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(palette: p, now: store.now(), active: widget.readOnly ? '규칙' : null,
                  tabs: widget.readOnly ? navTabs(context, store, active: '규칙') : const []),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: 'CONNECT 2400 ... ', style: termStyle(p.dim, size: 13)),
                      TextSpan(text: 'OK', style: termStyle(p.cmd, size: 13)),
                    ])),
                    const SizedBox(height: 10),
                    Text('오늘의 글감 게시판', style: termStyle(p.hi, size: 18, weight: FontWeight.w700, ko: true)),
                    const SizedBox(height: 4),
                    Text(
                      '매일 자정에 글감이 하나 열려요. 선착순 20명이 익명으로 한 편씩, 300자 안에 써요. '
                      '직접 쓴 글도, 좋아하는 소설의 한 구절도 좋아요.',
                      style: termStyle(p.dim, size: 13, ko: true),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border.all(color: p.line)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('익명 이름', style: termStyle(p.dim, size: 12)),
                          Text('guest_0000', style: termStyle(p.cmd, size: 18)),
                          Text('매일 자정에 새 이름이 붙어요. 가입 · 실명 · 연락처 없음.',
                              style: termStyle(p.dim, size: 12, ko: true)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                      TextSpan(text: 'type rules.txt', style: termStyle(p.cmd)),
                    ])),
                    const SizedBox(height: 8),
                    for (final (i, r) in inkRules.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('[${i + 1}]', style: termStyle(p.cmd, size: 13)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(r, style: termStyle(p.fg, size: 13, ko: true))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text('문의 · 신고 처리: github.com/isla0x/ink-exe/issues',
                        style: termStyle(p.dim, size: 12)),
                    if (widget.readOnly) ...[
                      const SizedBox(height: 18),
                      Text('차단한 사람 ${store.blocked.length}명', style: termStyle(p.fg, size: 13)),
                      const SizedBox(height: 8),
                      if (store.blocked.isNotEmpty)
                        TermBoxButton(palette: p, label: '차단 모두 풀기', textColor: p.cmd, onTap: store.unblockAll),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: widget.readOnly
                      ? TermWideButton(
                          palette: p,
                          keyLabel: '[ ESC ]',
                          label: '게시판으로',
                          onTap: () => Navigator.of(context).maybePop(),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Semantics(
                              checked: _checked,
                              child: InkWell(
                                onTap: () => setState(() => _checked = !_checked),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minHeight: 48),
                                  child: Row(
                                    children: [
                                      Text(_checked ? '[x]' : '[ ]', style: termStyle(p.cmd)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text('위 규칙과 이용약관에 동의하고, 만 14세 이상이에요.',
                                            style: termStyle(p.fg, size: 13, ko: true)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Opacity(
                              opacity: _checked ? 1 : 0.4,
                              child: IgnorePointer(
                                ignoring: !_checked,
                                child: TermWideButton(
                                  palette: p,
                                  keyLabel: '[ ENTER ]',
                                  label: '입장하기',
                                  onTap: _enter,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
