import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../widgets/entry_card.dart';
import '../widgets/pen_panel.dart';
import '../widgets/term_widgets.dart';
import '../theme/term_palette.dart';
import 'nav_tabs.dart';

/// 내가 쓴 글 모아 보기.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.store});

  final InkStore store;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  InkError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.store.loadPen();
    widget.store.loadMine().then((err) {
      if (mounted) {
        setState(() {
          _error = err;
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.palette;
        final list = store.mine;
        return Scaffold(
          backgroundColor: p.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(palette: p, now: store.now(), active: 'log', tabs: navTabs(context, store, active: 'log')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                      TextSpan(text: 'log --mine', style: termStyle(p.cmd)),
                    ])),
                    if (store.shop != null) PenPanel(store: store),
                    _ThemeRow(store: store),
                    Text('내가 쓴 글 ${list.length}편', style: termStyle(p.hi, ko: true)),
                    Text('이 기기에서 쓴 글이에요. 앱을 지우면 목록도 사라져요.', style: termStyle(p.dim, size: 12, ko: true)),
                    const SizedBox(height: 8),
                    if (_loading)
                      Text('LOADING ...', style: termStyle(p.dim, size: 13))
                    else if (_error != null)
                      Text(_error!.message, style: termStyle(p.warn, size: 13, ko: true))
                    else if (list.isEmpty)
                      Text('아직 쓴 글이 없어요.', style: termStyle(p.dim, size: 13, ko: true))
                    else
                      for (final e in list)
                        EntryCard(
                          entry: e,
                          palette: p,
                          expanded: true,
                          blocked: false,
                          header: '${shortDate(e.day)} · ${e.topic ?? ''}',
                        ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TermWideButton(
                    palette: p,
                    keyLabel: '[ ESC ]',
                    label: '게시판으로',
                    onTap: () => Navigator.of(context).maybePop(),
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

/// 화면 모드: [자동] [다크] [라이트]
class _ThemeRow extends StatelessWidget {
  const _ThemeRow({required this.store});

  final InkStore store;

  static const _labels = {'auto': '자동', 'dark': '다크', 'light': '라이트'};

  @override
  Widget build(BuildContext context) {
    final p = store.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('화면', style: termStyle(p.dim, size: 12, ko: true)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final m in InkStore.themeModes) ...[
                if (m != InkStore.themeModes.first) const SizedBox(width: 8),
                Expanded(
                  child: TermBoxButton(
                    palette: p,
                    label: _labels[m]!,
                    selected: store.themeMode == m,
                    semanticLabel: '화면 ${_labels[m]}',
                    onTap: () => store.setThemeMode(m),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            store.themeMode == 'auto' ? '아이폰 설정(다크 모드)을 따라가요. 홈 화면 위젯도 같아요.' : '홈 화면 위젯도 같은 색으로 바뀌어요.',
            style: termStyle(p.dim, size: 11, ko: true),
          ),
        ],
      ),
    );
  }
}
