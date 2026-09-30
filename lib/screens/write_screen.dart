import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/term_widgets.dart';

/// 글쓰기: 글감 · [창작]/[인용] · 본문 300자 · (인용) 작품명 · 작가.
class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, required this.store});

  final InkStore store;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> {
  final _body = TextEditingController();
  final _title = TextEditingController();
  final _author = TextEditingController();
  EntryKind _kind = EntryKind.original;
  bool _sending = false;
  String? _error;

  InkStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    for (final c in [_body, _title, _author]) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() => _error = null);

  @override
  void dispose() {
    for (final c in [_body, _title, _author]) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  int get _len => _body.text.trim().runes.length;

  bool get _ready {
    final max = store.board?.maxLen ?? 300;
    if (_len == 0 || _len > max || _sending) return false;
    if (_kind == EntryKind.quote && (_title.text.trim().isEmpty || _author.text.trim().isEmpty)) return false;
    return true;
  }

  Future<void> _send() async {
    if (!_ready) return;
    setState(() => _sending = true);
    final err = await store.submit(
      _body.text,
      kind: _kind,
      title: _kind == EntryKind.quote ? _title.text : null,
      author: _kind == EntryKind.quote ? _author.text : null,
    );
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _sending = false;
      _error = err.message;
    });
    // 자리가 다 찼거나 이미 썼으면 더 쓸 수 없으니 잠깐 보여주고 돌아간다.
    if (err.code == 'full' || err.code == 'already' || err.code == 'banned') {
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) Navigator.of(context).maybePop(false);
    }
  }

  InputDecoration _deco(TermPalette p, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: termStyle(p.dim, size: 14, ko: true),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: p.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: p.cmd)),
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.palette;
        final b = store.board;
        final max = b?.maxLen ?? 300;
        final over = _len > max;
        return Scaffold(
          backgroundColor: p.bg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TitleBar(palette: p, now: store.now(), active: 'write', tabs: [('write', null)]),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                      TextSpan(text: 'write #${two((b?.count ?? 0) + 1)}', style: termStyle(p.cmd)),
                    ])),
                    const SizedBox(height: 4),
                    Text('글감', style: termStyle(p.dim, size: 12)),
                    Text(b?.topic ?? '', style: termStyle(p.hi, size: 22, weight: FontWeight.w700, ko: true)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TermBoxButton(
                          palette: p,
                          label: '창작',
                          selected: _kind == EntryKind.original,
                          onTap: () => setState(() => _kind = EntryKind.original),
                        ),
                        const SizedBox(width: 8),
                        TermBoxButton(
                          palette: p,
                          label: '인용',
                          selected: _kind == EntryKind.quote,
                          onTap: () => setState(() => _kind = EntryKind.quote),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_kind == EntryKind.quote) ...[
                      Text('좋아하는 작품의 한 구절이면 출처를 꼭 적어 주세요.', style: termStyle(p.dim, size: 12, ko: true)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Semantics(
                              label: '작품명',
                              child: TextField(
                                controller: _title,
                                maxLength: 60,
                                style: termStyle(p.hi, size: 15, height: 1.3, ko: true),
                                cursorColor: p.cmd,
                                keyboardAppearance: p.isLight ? Brightness.light : Brightness.dark,
                                decoration: _deco(p, '작품명'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: Semantics(
                              label: '작가',
                              child: TextField(
                                controller: _author,
                                maxLength: 40,
                                style: termStyle(p.hi, size: 15, height: 1.3, ko: true),
                                cursorColor: p.cmd,
                                keyboardAppearance: p.isLight ? Brightness.light : Brightness.dark,
                                decoration: _deco(p, '작가'),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    Semantics(
                      label: _kind == EntryKind.quote ? '옮겨 적을 구절' : '글',
                      child: TextField(
                        controller: _body,
                        minLines: 8,
                        maxLines: 14,
                        keyboardType: TextInputType.multiline,
                        inputFormatters: [LengthLimitingTextInputFormatter(max + 20)],
                        style: termStyle(p.hi, size: 15, height: 1.6, ko: true),
                        cursorColor: p.cmd,
                        keyboardAppearance: p.isLight ? Brightness.light : Brightness.dark,
                        decoration: _deco(p, _kind == EntryKind.quote ? '옮겨 적을 구절' : '글감으로 떠오른 장면을 써 보세요'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _kind == EntryKind.quote
                                ? '인용도 출처와 함께 명예의 전당에 오를 수 있어요.'
                                : '한 번 올리면 고칠 수 없어요. 지우기만 할 수 있어요.',
                            style: termStyle(p.dim, size: 12, ko: true),
                          ),
                        ),
                        Text('$_len/$max', style: termStyle(over ? p.warn : p.dim, size: 12)),
                      ],
                    ),
                    if (_error != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!, style: termStyle(p.warn, size: 13, ko: true)),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Opacity(
                        opacity: _ready ? 1 : 0.4,
                        child: IgnorePointer(
                          ignoring: !_ready,
                          child: TermWideButton(
                            palette: p,
                            keyLabel: '[ ENTER ]',
                            label: _sending ? '올리는 중...' : '올리기',
                            onTap: _send,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TermBoxButton(palette: p, label: '[ ESC ] 닫기', onTap: () => Navigator.of(context).maybePop()),
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
