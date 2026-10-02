import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../state/ink_store.dart';
import '../theme/term_palette.dart';
import '../widgets/term_widgets.dart';

/// 이용약관 (EULA) 전문. docs/terms.html 과 같은 내용 + 영어 요약.
const inkTerms = <(String, List<String>)>[
  ('1. 서비스', [
    'ink.exe 는 매일 주어지는 글감으로 이용자가 익명으로 짧은 글을 올리고 읽는 게시판입니다. 가입 없이 기기마다 익명 식별자가 쓰입니다.',
  ]),
  ('2. 이용 조건', [
    '만 18세 이상만 이용할 수 있습니다.',
    '처음 열 때 이 약관(EULA)과 커뮤니티 규칙에 동의해야 이용할 수 있습니다.',
  ]),
  ('3. 무관용 원칙', [
    '부적절한 글(욕설 · 비방 · 혐오 · 차별 · 성적인 글, 폭력이나 자해를 부추기는 글, 개인정보, 광고 · 도배, 사칭, 불법)과 다른 사람을 괴롭히는 이용자에게는 무관용 원칙을 적용합니다.',
    '이런 글은 경고 없이 지우고, 쓴 사람(기기)은 게시판에서 영구히 내보냅니다.',
  ]),
  ('4. 걸러내기 · 신고 · 차단', [
    '금지어가 들어간 글과 링크는 올라가지 않습니다.',
    '모든 글의 ⋯ 메뉴에서 신고할 수 있고, 신고한 글은 바로 내 화면에서 사라집니다. 신고가 3번 쌓이면 모두에게 가려집니다.',
    '같은 메뉴에서 작성자를 차단하면 그 사람의 글이 바로, 앞으로도 계속 보이지 않습니다.',
    '내 글은 언제든 바로 지울 수 있습니다.',
  ]),
  ('5. 운영자의 조치', [
    '운영자는 신고를 받은 뒤 24시간 안에 확인해, 규칙을 어긴 글을 지우고 그 글을 쓴 이용자(기기)를 내보냅니다.',
  ]),
  ('6. 글의 권리', [
    '글의 저작권은 쓴 사람에게 있습니다. 앱이 그 글을 게시판 · 명예의 전당에 보여줄 수 있도록 허락합니다. 인용한 구절의 권리는 원저작자에게 있습니다.',
  ]),
  ('7. 펜네임 (유료)', [
    '펜네임은 한 번 사는 인앱 상품입니다. 결제 · 환불은 Apple · Google 정책을 따릅니다. 규칙에 어긋나는 펜네임은 지울 수 있습니다.',
  ]),
  ('8. 책임의 한계 · 변경', [
    '게시글은 이용자 각자의 글이며 운영자의 의견이 아닙니다. 약관이 바뀌면 앱과 웹페이지에 알립니다.',
  ]),
];

const _english =
    'End User License Agreement (summary). You must be 18 or older. There is zero tolerance for objectionable '
    'content (abuse, harassment, hate, sexual content, violence or self-harm, personal information, spam, '
    'impersonation, illegal content) and for abusive users. Posts with banned words or links are filtered. '
    'Any post can be reported from its ⋯ menu; a reported post is removed from your feed immediately, and '
    'posts with 3 reports are hidden for everyone. You can block an author to hide all of their posts '
    'immediately. The developer reviews every report within 24 hours, removes the content and ejects the '
    'user (device) who posted it. Contact: $contactEmail';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, required this.store});

  final InkStore store;

  @override
  Widget build(BuildContext context) {
    final p = store.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleBar(palette: p, now: store.now()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              children: [
                Text.rich(TextSpan(children: [
                  TextSpan(text: 'C:\\ink> ', style: termStyle(p.dim)),
                  TextSpan(text: 'type eula.txt', style: termStyle(p.cmd)),
                ])),
                const SizedBox(height: 10),
                Text('이용약관 (EULA)', style: termStyle(p.hi, size: 18, weight: FontWeight.w700, ko: true)),
                Text('시행일: 2026년 10월 2일', style: termStyle(p.dim, size: 12, ko: true)),
                const SizedBox(height: 12),
                for (final (title, lines) in inkTerms) ...[
                  Text(title, style: termStyle(p.cmd, size: 14, weight: FontWeight.w700, ko: true)),
                  const SizedBox(height: 4),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(l, style: termStyle(p.fg, size: 13, ko: true)),
                    ),
                  const SizedBox(height: 10),
                ],
                Text('9. 문의 · 신고', style: termStyle(p.cmd, size: 14, weight: FontWeight.w700, ko: true)),
                const SizedBox(height: 4),
                ContactLine(store: store),
                const SizedBox(height: 18),
                DashedDivider(color: p.line),
                const SizedBox(height: 12),
                Text(_english, style: termStyle(p.dim, size: 12)),
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
                label: '돌아가기',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `문의 · 신고: islaay@naver.com` — 누르면 주소를 복사한다.
class ContactLine extends StatelessWidget {
  const ContactLine({super.key, required this.store});

  final InkStore store;

  @override
  Widget build(BuildContext context) {
    final p = store.palette;
    return Semantics(
      button: true,
      label: '문의 및 신고 이메일 $contactEmail, 눌러서 복사',
      excludeSemantics: true,
      child: InkWell(
        onTap: () {
          Clipboard.setData(const ClipboardData(text: contactEmail));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              backgroundColor: p.bar,
              content: Text('$contactEmail 복사했어요', style: termStyle(p.ok, size: 13, ko: true)),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '문의 · 신고: ', style: termStyle(p.dim, size: 13, ko: true)),
              TextSpan(
                text: contactEmail,
                style: termStyle(p.cmd, size: 13, decoration: TextDecoration.underline),
              ),
              TextSpan(text: '  (누르면 복사)', style: termStyle(p.dim, size: 12, ko: true)),
            ])),
          ),
        ),
      ),
    );
  }
}
