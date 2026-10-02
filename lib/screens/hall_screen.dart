import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/entry_card.dart';
import '../widgets/term_widgets.dart';
import 'nav_tabs.dart';

/// 명예의 전당: 오늘 지금 1위 · 이번 달 날마다 1위 · 지난달들의 이달의 1위.
class HallScreen extends StatefulWidget {
  const HallScreen({super.key, required this.store});

  final InkStore store;

  @override
  State<HallScreen> createState() => _HallScreenState();
}

class _HallScreenState extends State<HallScreen> {
  InkError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final err = await widget.store.loadHall();
    if (mounted) {
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  Widget _section(TermPalette p, String title, String? sub) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: termStyle(p.hi, ko: true)),
            if (sub != null) Text(sub, style: termStyle(p.dim, size: 12, ko: true)),
          ],
        ),
      );

  String _dayHeader(Entry e) => '${shortDate(e.day)} · ${e.topic ?? ''}';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.palette;
        final h = store.hall;
        Widget card(Entry e, String header) => EntryCard(
              entry: e,
              palette: p,
              expanded: true,
              blocked: store.blocked.contains(e.author),
              reported: store.reported.contains(e.id),
              header: header,
            );
        return Scaffold(
          backgroundColor: p.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(palette: p, now: store.now(), active: 'hall', tabs: navTabs(context, store, active: 'hall')),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                      TextSpan(text: 'type hall.txt', style: termStyle(p.cmd)),
                    ])),
                    Text('명예의 전당', style: termStyle(p.hi, size: 22, weight: FontWeight.w700, ko: true)),
                    Text('날마다 +1 1위 글이 이달 전당에 오르고, 달이 끝나면 그중 한 편만 남아요.',
                        style: termStyle(p.dim, size: 12, ko: true)),
                    if (_loading)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Text('LOADING ...', style: termStyle(p.dim, size: 13)),
                      )
                    else if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Text(_error!.message, style: termStyle(p.warn, size: 13, ko: true)),
                      )
                    else ...[
                      if (h.today != null) ...[
                        _section(p, '오늘 지금 1위', '자정에 확정돼요'),
                        card(h.today!, _dayHeader(h.today!)),
                      ],
                      _section(p, '${h.monthLabel} · 날마다 1위', null),
                      if (h.month.isEmpty)
                        Text('아직 비어 있어요. 오늘 +1을 가장 많이 받은 글이 내일 여기 올라와요.',
                            style: termStyle(p.dim, size: 13, ko: true))
                      else
                        for (final e in h.month) card(e, _dayHeader(e)),
                      _section(p, '이달의 1위', '달마다 한 편, 영구 보관'),
                      if (h.champions.isEmpty)
                        Text('첫 달이 끝나면 여기에 첫 번째 이달의 1위가 남아요.', style: termStyle(p.dim, size: 13, ko: true))
                      else
                        for (final e in h.champions) card(e, '${e.month ?? ''} · ${_dayHeader(e)}'),
                    ],
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
