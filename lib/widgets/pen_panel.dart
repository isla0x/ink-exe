import 'package:flutter/material.dart';

import '../data/models.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import 'term_widgets.dart';

/// log 화면 맨 위의 펜네임 칸: 사기 · 복원 · 정하기 · 바꾸기.
class PenPanel extends StatelessWidget {
  const PenPanel({super.key, required this.store});

  final InkStore store;

  @override
  Widget build(BuildContext context) {
    final p = store.palette;
    final pen = store.pen;
    final notice = store.penNotice;
    final wait = pen.nextChange;

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: pen.owned ? p.cmd : p.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('펜네임', style: termStyle(p.dim, size: 12, ko: true)),
              const Spacer(),
              if (pen.owned) Text('[보유]', style: termStyle(p.cmd, size: 12, ko: true)),
            ],
          ),
          const SizedBox(height: 4),
          if (!pen.owned) ...[
            Text('guest_0000 대신 내 이름으로', style: termStyle(p.hi, size: 16, weight: FontWeight.w700, ko: true)),
            const SizedBox(height: 4),
            Text(
              '지금은 날마다 바뀌는 guest 이름으로 올라가요. 펜네임을 사면 올리는 글과 명예의 전당에 내 이름이 남아요. 한 번 사면 계속 쓸 수 있어요.',
              style: termStyle(p.dim, size: 12, height: 1.5, ko: true),
            ),
            const SizedBox(height: 10),
            _Dim(
              off: store.penBusy,
              child: TermWideButton(
                palette: p,
                keyLabel: '[ \$ ]',
                label: store.penPrice == null ? '펜네임 사기' : '펜네임 사기 · ${store.penPrice}',
                onTap: store.buyPen,
              ),
            ),
            const SizedBox(height: 6),
            _Dim(
              off: store.penBusy,
              child: TermBoxButton(palette: p, label: '구매 복원', onTap: store.restorePen),
            ),
          ] else if (pen.name == null) ...[
            Text('펜네임을 정해 주세요', style: termStyle(p.hi, size: 16, weight: FontWeight.w700, ko: true)),
            const SizedBox(height: 4),
            Text('정한 뒤로 올리는 글에 붙어요.', style: termStyle(p.dim, size: 12, ko: true)),
            const SizedBox(height: 10),
            TermWideButton(
              palette: p,
              keyLabel: '[ ENTER ]',
              label: '이름 정하기',
              onTap: () => showPenNameSheet(context, store),
            ),
          ] else ...[
            Text(pen.name!, style: termStyle(p.cmd, size: 20, weight: FontWeight.w700, ko: true)),
            const SizedBox(height: 4),
            Text(
              wait == null
                  ? '오늘부터 올리는 글에 붙어요. 7일에 한 번 바꿀 수 있어요.'
                  : '${two(wait.month)}.${two(wait.day)} ${two(wait.hour)}:${two(wait.minute)} 이후에 바꿀 수 있어요.',
              style: termStyle(p.dim, size: 12, ko: true),
            ),
            const SizedBox(height: 10),
            _Dim(
              off: wait != null,
              child: TermBoxButton(palette: p, label: '펜네임 바꾸기', onTap: () => showPenNameSheet(context, store)),
            ),
          ],
          if (notice != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  notice.$2,
                  style: termStyle(notice.$1 == 'err' ? p.warn : (notice.$1 == 'ok' ? p.ok : p.dim), size: 12, ko: true),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dim extends StatelessWidget {
  const _Dim({required this.off, required this.child});

  final bool off;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Opacity(opacity: off ? 0.4 : 1, child: IgnorePointer(ignoring: off, child: child));
}

/// 펜네임 입력 시트.
Future<void> showPenNameSheet(BuildContext context, InkStore store) {
  final p = store.palette;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.bar,
    shape: RoundedRectangleBorder(side: BorderSide(color: p.cmd)),
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheet).bottom),
      child: SafeArea(child: _PenNameForm(store: store, palette: p)),
    ),
  );
}

class _PenNameForm extends StatefulWidget {
  const _PenNameForm({required this.store, required this.palette});

  final InkStore store;
  final TermPalette palette;

  @override
  State<_PenNameForm> createState() => _PenNameFormState();
}

class _PenNameFormState extends State<_PenNameForm> {
  late final _c = TextEditingController(text: widget.store.pen.name ?? '');
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_sending) return;
    setState(() => _sending = true);
    final err = await widget.store.setPen(_c.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _sending = false;
        _error = err.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('C:\\ink> pen --set', style: termStyle(p.dim, size: 13)),
          const SizedBox(height: 8),
          Semantics(
            label: '펜네임',
            child: TextField(
              controller: _c,
              autofocus: true,
              maxLength: 12,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) => setState(() => _error = null),
              style: termStyle(p.hi, size: 16, ko: true),
              cursorColor: p.cmd,
              keyboardAppearance: p.isLight ? Brightness.light : Brightness.dark,
              decoration: InputDecoration(
                hintText: '펜네임 (2~12자)',
                hintStyle: termStyle(p.dim, size: 14, ko: true),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: p.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: p.cmd)),
                counterStyle: termStyle(p.dim, size: 11),
              ),
            ),
          ),
          Text(
            '한글 · 영문 · 숫자 · _ 만, 띄어쓰기 없이. 겹치는 이름은 안 돼요.\n정하면 7일 동안 바꿀 수 없어요. 개인정보(실명 · 연락처 · SNS 아이디)는 넣지 마세요.',
            style: termStyle(p.dim, size: 12, height: 1.5, ko: true),
          ),
          if (_error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: termStyle(p.warn, size: 13, ko: true)),
              ),
            ),
          const SizedBox(height: 12),
          TermWideButton(
            palette: p,
            keyLabel: '[ ENTER ]',
            label: _sending ? '저장하는 중...' : '정하기',
            onTap: _save,
          ),
        ],
      ),
    );
  }
}
