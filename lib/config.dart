/// 서버 주소. Supabase 대시보드 → Project Settings → API 의 값.
///
/// anon 키는 원래 앱 안에 들어가는 공개용 키라 저장소에 있어도 된다.
/// (쓰기 권한은 supabase/schema.sql 의 함수와 RLS 가 막는다)
/// `--dart-define=SUPABASE_URL=` 처럼 빈 값을 주면 서버 없이 데모 모드로 돈다.
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://eqadkyrdcpdjomvhpkgi.supabase.co');
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_AbU7JlZV_FAoXJXdwE9egg_YUKtu94V',
);

/// 신고 · 문의 연락처 (앱 안 규칙 · 약관 화면과 docs/ 에 보인다).
const contactEmail = 'islaay@naver.com';

bool get hasServer => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
