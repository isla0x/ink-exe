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
- **기기 묶기**: 하루 한 편 · +1 · 신고 · 쓰기 금지를 기기 단위로 센다. 앱을 지웠다 다시 깔아 새 익명 사용자가 돼도 같은 기기로 알아본다 (iOS 키체인 UUID · Android ANDROID_ID → `bind_device`, 서버에는 SHA-256 해시만 저장)
- **명예의 전당**: 날마다 +1 1위 글(인용 포함, 설정으로 끌 수 있음) → 달이 끝나면 그 달 1위 한 편만 영구 보관
- **내 글(log)**
- **위젯**(iOS 홈 화면 작게 · 중간, 잠금화면): 오늘 글감 · 남은 자리 · 마감 카운트다운 · 지금 1위. `ios/InkWidget`, 서버 `board_status()` 를 직접 부른다
- **펜네임 (유료, 한 번 구매)**: log 화면에서 산다. 올리는 글에 guest 이름 대신 붙고, 7일에 한 번 바꿀 수 있다. 구매 복원 지원

## 서버 (Supabase)

1. Supabase 프로젝트 생성 (Seoul), Authentication → Sign In / Providers → **Allow anonymous sign-ins** 켜기
2. SQL Editor 에 `supabase/schema.sql` 붙여 넣고 Run (다시 실행해도 안전)
3. `lib/config.dart` 에 Project URL · anon 키 (또는 `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`)
4. 펜네임: Edge Functions → Deploy a new function → Via Editor, 이름 `claim-pen`, `supabase/functions/claim-pen/index.ts` 를 통째로 붙여 넣고 Deploy
   (또는 `supabase functions deploy claim-pen --project-ref <ref>`). App Store Connect · Google Play Console 에 비소모성 상품 `ink_exe_pen` 생성.
   안드로이드: 함수 Secrets 에 `GOOGLE_PLAY_PUBLIC_KEY` (Play Console → 수익 창출 설정 → 라이선스의 Base64 공개키)
   함수 Settings 의 **Verify JWT with legacy secret 은 끈다** (프로젝트가 ES256 서명 키를 써서 사용자 토큰이 legacy 검사를 못 통과한다. 로그인 확인은 함수 코드가 직접 한다)

### 펜네임 결제 확인
앱이 받은 영수증을 `claim-pen` 함수로 보낸다. 안드로이드는 구매 원본 JSON 과 서명을 보내고, 함수가 Google Play 라이선스 공개키(SHA1withRSA)로 확인한다.
iOS 는 StoreKit 2 거래 영수증(JWS). 함수는 Apple 인증서 체인(Apple Root CA G3 지문) ·
ES256 서명 · 번들 ID · 상품 ID · 환불 여부를 확인한 뒤 service_role 로 `ink_grant_pen` 을 부른다. 외부 키(.p8)는 필요 없다.
앱은 `ink_grant_pen` 을 직접 부를 수 없다. 테스트: `deno test --allow-net --allow-env --allow-read supabase/functions/claim-pen/test.ts`

앱은 테이블에 직접 접근하지 못하고(RLS + 권한 회수) RPC 함수만 부른다:
`get_board` · `post_entry` · `toggle_like` · `report_post` · `delete_my_post` · `my_posts` · `get_hall` · `board_status` · `my_pen` · `set_pen`.

운영(대시보드 Table Editor): `ink_settings`(인원 · 글자 수 · 신고 기준), `ink_posts.hidden`, `ink_bans`, `ink_banned_words`, `ink_topics`, `ink_pens.name`(부적절한 펜네임 지우기).

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
  state/ink_store.dart    상태, 30초마다 새로 고침, 자정 카운트다운, 펜네임
  state/pen_shop.dart     인앱결제 (in_app_purchase, StoreKit 2)
  screens/                rules · board · write · hall · log
supabase/schema.sql       테이블 · RPC · 권한
supabase/test/            규칙 테스트
supabase/functions/claim-pen/  펜네임 결제 확인 (Edge Function)
```
