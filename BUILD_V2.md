# ink.exe 2.0.0

## 추가 기능: 비공개 내 글 서랍

제목줄의 `서랍`에서 새 비공개 초안을 만들고 수정할 수 있습니다. 글쓰기 화면에서도 초안이 자동 저장됩니다. 공개 게시판의 자리가 차거나 글감이 바뀌어도 작성한 글은 기기에 남습니다. 비공개 초안은 서버에 게시하지 않습니다.

이 폴더에 기능을 추가한 소스가 들어 있습니다. GitHub main에는 아직 반영하지 않았습니다.

Mac 터미널에서:

```bash
cd "/Users/chaen/Documents/Codex/2026-10-23/new-chat-2/apps/ink-exe-main"
bash tool/build_v2.sh
```

기본 빌드 번호는 12입니다. App Store Connect에 이미 사용한 번호라면 더 큰 숫자를 인자로 넣으세요.

```bash
bash tool/build_v2.sh 13
```

스크립트는 의존성을 받고 IPA를 빌드한 다음 Xcode 아카이브를 엽니다. Xcode의 Distribute App → App Store Connect에서 업로드합니다. 처음에는 Runner의 Signing & Capabilities에서 본인 개발팀이 선택되어 있어야 합니다.

검사:

```bash
flutter analyze --no-fatal-infos
flutter test
```

이 작업 환경에서는 정적 검사를 실행했습니다. Flutter 실행 테스트는 로컬 서버 소켓 생성 권한 제한으로 실행하지 못했습니다. 서명된 IPA 빌드 및 업로드는 실행하지 않았습니다.
