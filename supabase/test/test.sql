-- ink.exe 서버 규칙 테스트. run.sh 가 스키마를 올린 뒤 실행한다.
\set ON_ERROR_STOP on
set client_min_messages = warning;

create schema if not exists t;
grant usage on schema t to anon, authenticated, service_role;

-- 이 사용자로 바꾼다 (Supabase 로그인 흉내).
create or replace function t.u(n int) returns uuid language sql immutable as $$
  select ('00000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid
$$;
grant execute on function t.u(int) to anon, authenticated, service_role;

-- sql 을 실행했을 때 정확히 이 에러가 나야 한다.
create or replace function t.expect(q text, code text) returns void language plpgsql as $$
declare ok boolean := false;
begin
  begin
    execute q;
  exception when others then
    if sqlerrm = code then ok := true;
    else raise exception 'expected %, got % (%)', code, sqlerrm, q; end if;
  end;
  if not ok then raise exception 'expected %, but no error (%)', code, q; end if;
end $$;
grant execute on function t.expect(text, text) to anon, authenticated;

-- 2026-10-01 (목) 00:00:05 KST 에 게시판이 열린다.
set ink.fake_now = '2026-10-01 00:00:05+09';

-- ── 1. 로그인 없이: 읽기는 되고 쓰기는 안 된다 ──
set role anon;
do $$ begin
  assert (public.get_board() ->> 'topic') = '파란 나무', '10.01 글감은 풀의 첫 번째';
  assert (public.get_board() ->> 'count')::int = 0;
  assert (public.board_status() ->> 'cap')::int = 20;
end $$;
select t.expect($q$ select public.post_entry('안녕') $q$, 'permission denied for function post_entry');
select t.expect($q$ select * from public.ink_posts $q$, 'permission denied for table ink_posts');
reset role;

-- ── 2. 입력 검사 ──
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
select t.expect($q$ select public.post_entry('   ') $q$, 'ink:empty');
select t.expect($q$ select public.post_entry(repeat('가', 301)) $q$, 'ink:too_long');
select t.expect($q$ select public.post_entry('여기 와 https://spam.example') $q$, 'ink:link');
select t.expect($q$ select public.post_entry('내 블로그 abc.com 놀러와') $q$, 'ink:link');
select t.expect($q$ select public.post_entry('이 시 발 놈아') $q$, 'ink:word');
select t.expect($q$ select public.post_entry('구절', 'quote') $q$, 'ink:source');
select t.expect($q$ select public.post_entry('구절', 'quote', '데미안', '') $q$, 'ink:source');
select t.expect($q$ select public.post_entry('구절', 'poem') $q$, 'ink:source');
select t.expect($q$ select * from public.ink_posts $q$, 'permission denied for table ink_posts');
select t.expect($q$ update public.ink_settings set cap = 999 $q$, 'permission denied for table ink_settings');

-- 300자 딱 맞으면 된다. 줄바꿈은 정리된다.
do $$ declare r json; b json;
begin
  r := public.post_entry(E'  파란 나무 아래서\r\n\n\n\n' || repeat('가', 280) || '  ');
  assert (r ->> 'slot')::int = 1, 'first slot';
  b := public.get_board();
  assert (b -> 'posts' -> 0 ->> 'body') = E'파란 나무 아래서\n\n' || repeat('가', 280), 'body normalized';
  assert (b ->> 'mine_slot')::int = 1;
  assert (b -> 'posts' -> 0 ->> 'mine')::boolean;
  assert (b -> 'posts' -> 0 ->> 'nick') like 'guest\_____', 'nick shape';
end $$;
select t.expect($q$ select public.post_entry('두 번째') $q$, 'ink:already');

-- ── 3. 인용글 ──
select set_config('request.jwt.claim.sub', t.u(2)::text, false);
do $$ declare b json;
begin
  perform public.post_entry('새는 알에서 나오려고 투쟁한다.', 'quote', ' 데미안 ', '헤르만 헤세');
  b := public.get_board();
  assert (b -> 'posts' -> 1 ->> 'kind') = 'quote';
  assert (b -> 'posts' -> 1 ->> 'src_title') = '데미안';
  assert (b -> 'posts' -> 1 ->> 'src_author') = '헤르만 헤세';
end $$;

-- ── 4. 선착순 20 ──
do $$ begin
  for i in 3..20 loop
    perform set_config('request.jwt.claim.sub', t.u(i)::text, false);
    perform public.post_entry('글 ' || i);
  end loop;
end $$;
select set_config('request.jwt.claim.sub', t.u(21)::text, false);
select t.expect($q$ select public.post_entry('늦었다') $q$, 'ink:full');
do $$ begin
  assert (public.get_board() ->> 'count')::int = 20;
  assert public.get_board() ->> 'mine_slot' is null;
end $$;

-- ── 5. +1 ──
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
do $$ declare id1 bigint; id3 bigint; r json;
begin
  id1 := (public.get_board() -> 'posts' -> 0 ->> 'id')::bigint;
  id3 := (public.get_board() -> 'posts' -> 2 ->> 'id')::bigint;
  begin perform public.toggle_like(id1); raise exception 'no'; exception when others then assert sqlerrm = 'ink:own', sqlerrm; end;
  r := public.toggle_like(id3);
  assert (r ->> 'likes')::int = 1 and (r ->> 'liked')::boolean;
  r := public.toggle_like(id3);
  assert (r ->> 'likes')::int = 0 and not (r ->> 'liked')::boolean;
  -- 3번 글에 5명, 2번(인용)에 9명
  for i in 4..8 loop
    perform set_config('request.jwt.claim.sub', t.u(i)::text, false);
    perform public.toggle_like(id3);
  end loop;
  for i in 10..18 loop
    perform set_config('request.jwt.claim.sub', t.u(i)::text, false);
    perform public.toggle_like((public.get_board() -> 'posts' -> 1 ->> 'id')::bigint);
  end loop;
  perform set_config('request.jwt.claim.sub', t.u(1)::text, false);
  assert (public.get_board() -> 'posts' -> 2 ->> 'likes')::int = 5;
end $$;

-- ── 6. 신고 3번이면 가려지고, 본인에게만 보인다 ──
do $$ declare id5 bigint; r json;
begin
  id5 := (public.get_board() -> 'posts' -> 4 ->> 'id')::bigint;
  for i in 1..3 loop
    perform set_config('request.jwt.claim.sub', t.u(i)::text, false);
    r := public.report_post(id5, 'abuse');
    r := public.report_post(id5, 'abuse');  -- 같은 사람 두 번은 한 번
  end loop;
  assert (r ->> 'hidden')::boolean, 'hidden after 3';
  perform set_config('request.jwt.claim.sub', t.u(9)::text, false);
  assert (public.get_board() -> 'posts' -> 4 ->> 'body') is null, 'hidden for others';
  perform set_config('request.jwt.claim.sub', t.u(5)::text, false);
  assert (public.get_board() -> 'posts' -> 4 ->> 'body') = '글 5', 'author still sees';
end $$;

-- ── 7. 내 글 지우기: 자리는 그대로 ──
select set_config('request.jwt.claim.sub', t.u(20)::text, false);
do $$ declare id20 bigint;
begin
  id20 := (public.get_board() -> 'posts' -> 19 ->> 'id')::bigint;
  perform public.delete_my_post(id20);
  assert (public.get_board() -> 'posts' -> 19 ->> 'deleted')::boolean;
  assert (public.get_board() -> 'posts' -> 19 ->> 'body') is null;
  assert (public.get_board() ->> 'count')::int = 20, 'slot stays used';
end $$;
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
select t.expect($q$ select public.delete_my_post((public.get_board() -> 'posts' -> 1 ->> 'id')::bigint) $q$, 'ink:not_found');

-- ── 8. 다음 날: 새 게시판, 새 글감, 새 이름 ──
reset role;
set ink.fake_now = '2026-10-02 00:00:01+09';
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
do $$ declare b json; n1 text; n2 text;
begin
  b := public.get_board();
  assert (b ->> 'count')::int = 0;
  assert (b ->> 'topic') = '마지막 버스', 'next topic';
  assert (b ->> 'seconds_left')::int between 86390 and 86400;
  perform public.post_entry('다음 날');
  n1 := public.get_board(date '2026-10-01') -> 'posts' -> 0 ->> 'nick';
  n2 := public.get_board() -> 'posts' -> 0 ->> 'nick';
  assert (public.get_board(date '2026-10-01') -> 'posts' -> 0 ->> 'author')
       = (public.get_board() -> 'posts' -> 0 ->> 'author'), 'author stable';
  assert (public.get_board(date '2099-01-01') ->> 'day') = '2026-10-02', 'future clamps to today';
end $$;

-- ── 9. 명예의 전당: 이번 달은 날마다 1위 (인용글도 포함) ──
do $$ declare h json;
begin
  h := public.get_hall();
  assert json_array_length(h -> 'month') = 1, 'one day so far';
  assert (h -> 'month' -> 0 ->> 'body') = '새는 알에서 나오려고 투쟁한다.', 'quote (9) beats original (5)';
  assert (h -> 'month' -> 0 ->> 'src_title') = '데미안';
  assert (h -> 'month' -> 0 ->> 'topic') = '파란 나무';
  assert json_array_length(h -> 'champions') = 0;
end $$;

-- ── 10. 다음 달: 10월 1위 한 편만 '이달의 1위' ──
reset role;
set ink.fake_now = '2026-11-01 09:00:00+09';
set role authenticated;
do $$ declare h json;
begin
  -- 10.02 글에 +1 10개 → 10월 1위가 바뀐다 (인용 9개보다 많음)
  for i in 30..39 loop
    perform set_config('request.jwt.claim.sub', t.u(i)::text, false);
    perform public.toggle_like((public.get_board(date '2026-10-02') -> 'posts' -> 0 ->> 'id')::bigint);
  end loop;
  h := public.get_hall();
  assert json_array_length(h -> 'month') = 0, 'new month empty';
  assert json_array_length(h -> 'champions') = 1;
  assert (h -> 'champions' -> 0 ->> 'body') = '다음 날';
  assert (h -> 'champions' -> 0 ->> 'month') = '2026.10';
  assert (h -> 'champions' -> 0 ->> 'likes')::int = 10;
end $$;

-- ── 11. 차단된 사용자 · 내 글 모아보기 ──
reset role;
insert into public.ink_bans (user_id, reason) values (t.u(40), 'test');
update public.ink_settings set hall_includes_quotes = false;
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(40)::text, false);
select t.expect($q$ select public.post_entry('나도') $q$, 'ink:banned');
do $$ begin assert (public.get_board() ->> 'banned')::boolean; end $$;
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
do $$ declare m json;
begin
  m := public.my_posts();
  assert json_array_length(m) = 2;
  assert (m -> 0 ->> 'day') = '2026-10-02';
  assert (m -> 1 ->> 'topic') = '파란 나무';
end $$;
reset role;

-- 설정으로 인용글을 빼면 창작 1위(글 3)가 10.01 1위 후보가 된다.
reset role;
set ink.fake_now = '2026-10-02 12:00:00+09';
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(1)::text, false);
do $$ declare h json;
begin
  h := public.get_hall();
  assert (h -> 'month' -> 0 ->> 'body') = '글 3', 'quotes excluded by setting';
end $$;
reset role;

-- ── 12. 펜네임 ──
set ink.fake_now = '2026-10-03 09:00:00+09';
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(50)::text, false);
-- 앱은 결제 확인 함수를 직접 못 부른다 (공짜로 펜네임 얻기 방지).
select t.expect($q$ select public.ink_grant_pen(t.u(50), 'txn-1', 'Sandbox') $q$, 'permission denied for function ink_grant_pen');
select t.expect($q$ select * from public.ink_pens $q$, 'permission denied for table ink_pens');
do $$ begin assert not (public.my_pen() ->> 'owned')::boolean; end $$;
select t.expect($q$ select public.set_pen('작은새') $q$, 'ink:no_pen');
reset role;

set role service_role;
do $$ declare r json;
begin
  r := public.ink_grant_pen(t.u(50), 'txn-1', 'Sandbox');
  assert (r ->> 'owned')::boolean and r ->> 'name' is null;
  r := public.ink_grant_pen(t.u(50), 'txn-1', 'Sandbox');  -- 같은 영수증 두 번: 그대로
  assert (r ->> 'owned')::boolean;
  r := public.ink_grant_pen(t.u(51), 'txn-2', 'Sandbox');
end $$;
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub', t.u(50)::text, false);
select t.expect($q$ select public.set_pen('가') $q$, 'ink:pen_len');
select t.expect($q$ select public.set_pen('열세글자가넘는아주긴이름이다') $q$, 'ink:pen_len');
select t.expect($q$ select public.set_pen('작은 새') $q$, 'ink:pen_chars');
select t.expect($q$ select public.set_pen('abc.com') $q$, 'ink:pen_chars');
select t.expect($q$ select public.set_pen('01012345678') $q$, 'ink:pen_chars');
select t.expect($q$ select public.set_pen('guest_0001') $q$, 'ink:pen_reserved');
select t.expect($q$ select public.set_pen('Guest77') $q$, 'ink:pen_reserved');
select t.expect($q$ select public.set_pen('ink운영자') $q$, 'ink:pen_reserved');
select t.expect($q$ select public.set_pen('시발작가') $q$, 'ink:word');
do $$ declare r json;
begin
  r := public.set_pen('  작은새_7 ');
  assert r ->> 'name' = '작은새_7';
  assert r ->> 'next_change' is not null, '바꾼 뒤 7일 대기';
  r := public.set_pen('작은새_7');  -- 같은 이름은 그냥 통과
  assert r ->> 'name' = '작은새_7';
end $$;
select t.expect($q$ select public.set_pen('다른이름') $q$, 'ink:pen_wait');

-- 다른 사람은 같은 이름(대소문자 무시)을 못 쓴다.
select set_config('request.jwt.claim.sub', t.u(51)::text, false);
select t.expect($q$ select public.set_pen('작은새_7') $q$, 'ink:pen_taken');
do $$ begin assert public.set_pen('Moon') ->> 'name' = 'Moon'; end $$;
select set_config('request.jwt.claim.sub', t.u(50)::text, false);
reset role;

-- 펜네임으로 글을 쓰면 게시판 · 전당에 펜네임이 뜬다.
set role authenticated;
select public.post_entry('펜네임으로 쓴 글');
do $$ declare b json; p json;
begin
  b := public.get_board();
  select x into p from json_array_elements(b -> 'posts') x where x ->> 'body' = '펜네임으로 쓴 글';
  assert p ->> 'nick' = '작은새_7';
  assert (p ->> 'pen')::boolean;
  select x into p from json_array_elements(b -> 'posts') x where x ->> 'body' <> '펜네임으로 쓴 글' limit 1;
  assert p is null or not (p ->> 'pen')::boolean;
end $$;
reset role;

-- 7일 뒤에는 바꿀 수 있고, 지난 글의 이름은 그대로.
set ink.fake_now = '2026-10-10 09:00:01+09';
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(50)::text, false);
do $$ declare b json;
begin
  assert public.set_pen('큰새') ->> 'name' = '큰새';
  b := public.get_board('2026-10-03');
  assert exists (select 1 from json_array_elements(b -> 'posts') x where x ->> 'nick' = '작은새_7');
end $$;
reset role;

-- 구매 복원: 새 기기(새 사용자)로 같은 영수증이 오면 펜네임이 옮겨 간다.
set role service_role;
do $$ declare r json;
begin
  r := public.ink_grant_pen(t.u(60), 'txn-1', 'Sandbox');
  assert r ->> 'name' = '큰새';
end $$;
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', t.u(50)::text, false);
do $$ begin assert not (public.my_pen() ->> 'owned')::boolean, '옛 기기는 펜네임을 잃는다'; end $$;
select set_config('request.jwt.claim.sub', t.u(60)::text, false);
do $$ begin assert public.my_pen() ->> 'name' = '큰새'; end $$;
reset role;

select 'all db tests passed' as result;
