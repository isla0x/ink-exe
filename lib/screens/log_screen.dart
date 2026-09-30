import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../widgets/entry_card.dart';
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
