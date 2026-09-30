import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/term_palette.dart';

/// 글 한 편: `#03 guest_1234 00:12 [인용]    +5  ⋯` + 본문(접힘/펼침) + 출처.
class EntryCard extends StatelessWidget {
  const EntryCard({
    super.key,
    required this.entry,
    required this.palette,
    required this.expanded,
    required this.blocked,
    this.onTap,
    this.onLike,
    this.onMenu,
    this.header,
  });

  final Entry entry;
  final TermPalette palette;
  final bool expanded;
  final bool blocked;
  final VoidCallback? onTap;
  final VoidCallback? onLike;
  final VoidCallback? onMenu;

  /// 명예의 전당에서 날짜 · 글감 줄.
  final String? header;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final e = entry;

    String? placeholder;
    if (e.deleted) {
      placeholder = '(작성자가 지운 글)';
    } else if (e.hidden && !e.mine) {
      placeholder = '(신고가 쌓여 가려진 글)';
    } else if (blocked && !e.mine) {
      placeholder = '(차단한 사람의 글)';
    }
    final body = e.body ?? '';
    final long = body.length > 60 || body.contains('\n');

    return Container(
      decoration: BoxDecoration(
        color: e.mine ? p.cmd.withAlpha(p.isLight ? 18 : 22) : null,
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(header!, style: termStyle(p.cmd, size: 12, ko: true)),
            ),
          Row(
            children: [
              Text(e.slotLabel, style: termStyle(p.dim, size: 12)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  e.mine ? '${e.nick} (나)' : e.nick,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: termStyle(e.mine ? p.cmd : (e.pen ? p.hi : p.fg), size: 12, ko: e.pen),
                ),
              ),
              const SizedBox(width: 8),
              Text(e.time, style: termStyle(p.dim, size: 12)),
              if (e.isQuote && placeholder == null) ...[
                const SizedBox(width: 8),
                Text('[인용]', style: termStyle(p.tag, size: 12)),
              ],
              const Spacer(),
              if (onLike != null && placeholder == null)
                Semantics(
                  button: true,
                  selected: e.liked,
                  label: '공감 ${e.likes}${e.liked ? ', 누름' : ''}',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: e.mine ? null : onLike,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 52, minHeight: 36),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: e.liked ? p.cmd : null,
                        border: Border.all(color: e.liked ? p.cmd : p.line),
                      ),
                      child: Text('+${e.likes}', style: termStyle(e.liked ? p.bg : p.cmd, size: 12)),
                    ),
                  ),
                )
              else if (placeholder == null)
                Text('+${e.likes}', style: termStyle(p.cmd, size: 12)),
              if (onMenu != null && !e.deleted)
                Semantics(
                  button: true,
                  label: e.mine ? '내 글 메뉴' : '${e.slotLabel} 신고 또는 차단',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: onMenu,
                    child: SizedBox(
                      width: 44,
                      height: 40,
                      child: Center(child: Text('⋯', style: termStyle(p.dim, size: 16))),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (placeholder != null)
            Text(placeholder, style: termStyle(p.dim, size: 13, ko: true))
          else
            InkWell(
              onTap: long ? onTap : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    body,
                    maxLines: expanded ? null : 2,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: termStyle(p.hi, size: 14, ko: true, height: 1.6),
                  ),
                  if (e.source != null && (expanded || !long))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(e.source!, style: termStyle(p.tag, size: 12, ko: true)),
                    ),
                  if (long && !expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('더 보기 ▾', style: termStyle(p.dim, size: 12)),
                    ),
                  if (e.mine && e.hidden)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('신고가 쌓여 다른 사람에게는 가려졌어요.', style: termStyle(p.warn, size: 12, ko: true)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
