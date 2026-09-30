# ink.exe

매일 자정에 글감 하나. 선착순 20명이 익명으로 300자 안에 쓰는 짧은 글 게시판 (Flutter + Supabase).
[todo.exe](https://github.com/isla0x/todo-exe) · [diary.exe](https://github.com/isla0x/diary-exe) 시리즈.

```
C:\ink> topic
파란 나무
접속 [██████░░░░] 12/20  남은 자리 8
```

- **글감**: 매일 00:00 (KST) 바뀜. `supabase/schema.sql` 의 60개가 순서대로 돌고, `ink_topics` 에 날짜별로 지정 가능
- **쓰기**: 하루 한 편 · 300자 · 먼저 올린 순서대로 20명. [창작] / [인용](작품명 · 작가 필수)
- **+1**, **신고**(3번이면 자동 가림), **차단**(기기에 저장), 내 글 지우기(자리는 유지)
- **명예의 전당**: 날마다 +1 1위 글(인용 포함, 설정으로 끌 수 있음) → 달이 끝나면 그 달 1위 한 편만 영구 보관
- **내 글(log)**

## 서버 (Supabase)

1. Supabase 프로젝트 생성 (Seoul), Authentication → Sign In / Providers → **Allow anonymous sign-ins** 켜기
2. SQL Editor 에 `supabase/schema.sql` 붙여 넣고 Run (다시 실행해도 안전)
3. `lib/config.dart` 에 Project URL · anon 키 (또는 `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`)

앱은 테이블에 직접 접근하지 못하고(RLS + 권한 회수) RPC 함수만 부른다:
`get_board` · `post_entry` · `toggle_like` · `report_post` · `delete_my_post` · `my_posts` · `get_hall` · `board_status`.

운영(대시보드 Table Editor): `ink_settings`(인원 · 글자 수 · 신고 기준), `ink_posts.hidden`, `ink_bans`, `ink_banned_words`, `ink_topics`.

서버 규칙 테스트: `bash supabase/test/run.sh` (빈 Postgres 필요, CI 에서 자동 실행)

## 앱

```bash
flutter pub get
flutter test
open ios/Runner.xcworkspace
```

서버 주소가 비어 있으면 기기 안에서만 도는 데모 모드로 실행된다 (`lib/data/demo_api.dart`).

```
lib/
  data/models.dart        서버 JSON 모양
  data/supabase_api.dart  RPC 호출
  data/demo_api.dart      가짜 서버 (테스트 · 데모)
  state/ink_store.dart    상태, 30초마다 새로 고침, 자정 카운트다운
  screens/                rules · board · write · hall · log
supabase/schema.sql       테이블 · RPC · 권한
supabase/test/            규칙 테스트
```
