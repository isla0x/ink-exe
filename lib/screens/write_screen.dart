import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/draft.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/term_widgets.dart';

/// 글쓰기: 글감 · [창작]/[인용] · 본문 300자 · (인용) 작품명 · 작가.
class WriteScreen extends StatefulWidget {
  const WriteScreen({super.key, required this.store, this.draft, this.privateOnly = false});

  final Draft? draft;
  final bool privateOnly;

  final InkStore store;

  @override
  State<WriteScreen> createState() => _WriteScreenState();
}

class _WriteScreenState extends State<WriteScreen> with WidgetsBindingObserver {
  final _body = TextEditingController();
  final _title = TextEditingController();
  final _author = TextEditingController();
  EntryKind _kind = EntryKind.original;
  bool _sending = false;
  Timer? _draftTimer;
  late String _draftId, _draftDay, _draftTopic;
  bool _sent = false;
  String? _error;

  InkStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final d = widget.draft;
    _draftId = d?.id ?? DateTime.now().microsecondsSinceEpoch.toString();
    _draftDay = d?.day ?? (store.board?.day ?? store.now()).toIso8601String().substring(0, 10);
    _draftTopic = d?.topic ?? store.board?.topic ?? '자유 글감';
    _body.text = d?.body ?? '';
    _title.text = d?.title ?? '';
    _author.text = d?.author ?? '';
    _kind = d?.kind ?? EntryKind.original;
    for (final c in [_body, _title, _author]) {
      c.addListener(_changed);
    }
  }

  void _changed() {
    setState(() => _error = null);
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 350), () => _keepDraft());
  }

  Future<bool> _keepDraft() async {
    if (_sent || _body.text.trim().isEmpty) return false;
    try {
      await store.saveDraft(Draft(id: _draftId, day: _draftDay, topic: _draftTopic,
        body: _body.text, title: _title.text, author: _author.text, kind: _kind, updated: store.now()));
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = '초안을 저장하지 못했어요. 다시 시도해 주세요.');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) { _draftTimer?.cancel(); unawaited(_keepDraft()); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _draftTimer?.cancel();
    unawaited(_keepDraft());
    for (final c in [_body, _title, _author]) {
      c.removeListener(_changed);
      c.dispose();
    }
    super.dispose();
  }

  int get _len => _body.text.trim().runes.length;

  bool get _ready {
    final day = store.board?.day.toIso8601String().substring(0, 10);
    if (day != null && day != _draftDay) return false;
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
      _sent = true;
      _draftTimer?.cancel();
      try { await store.deleteDraft(_draftId); } catch (_) { /* Keep the local copy on write failure. */ }
      if (!mounted) return;
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
          // 빈 곳을 누르면 키보드를 내린다 (글 칸을 누른 건 칸이 먼저 받는다).
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
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
                    Text(widget.privateOnly ? '비공개 초안 · 내 기기에만 저장' : '글감', style: termStyle(p.dim, size: 12)),
                    Text(_draftTopic, style: termStyle(p.hi, size: 22, weight: FontWeight.w700, ko: true)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TermBoxButton(
                          palette: p,
                          label: '창작',
                          selected: _kind == EntryKind.original,
                          onTap: () { _kind = EntryKind.original; _changed(); },
                        ),
                        const SizedBox(width: 8),
                        TermBoxButton(
                          palette: p,
                          label: '인용',
                          selected: _kind == EntryKind.quote,
                          onTap: () { _kind = EntryKind.quote; _changed(); },
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
                            (b != null && b.day.toIso8601String().substring(0, 10) != _draftDay)
                                ? '글감이 바뀌었어요. 쓴 글은 내 서랍에 남아요.'
                                : _kind == EntryKind.quote
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
                      TermBoxButton(palette: p, label: '[ SAVE ] 내 서랍에 저장', onTap: () async {
                        _draftTimer?.cancel();
                        final saved = await _keepDraft();
                        if (!context.mounted) return;
                        if (saved) Navigator.of(context).pop();
                      }),
                      const SizedBox(height: 8),
                      if (!widget.privateOnly) Opacity(
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
          ),
        );
      },
    );
  }
}
