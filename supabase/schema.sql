-- ink.exe 서버 스키마 (Supabase / PostgreSQL)
--
-- Supabase 대시보드 → SQL Editor → New query 에 이 파일을 통째로 붙여 넣고 Run.
-- 여러 번 실행해도 안전하다 (create if not exists / create or replace).
--
-- 구조
--   · 테이블은 앱에서 직접 읽고 쓸 수 없다 (RLS 켜고 권한 회수).
--   · 앱은 아래 RPC 함수만 부른다. 함수 안에서 선착순 · 글자 수 · 하루 한 편 · 필터를 검사한다.
--   · 날짜는 한국 시간 자정 기준.
--
-- 운영 (대시보드 Table Editor)
--   · 선착순 인원 · 글자 수 · 신고 몇 번에 가릴지:  ink_settings
--   · 특정 날짜 글감 지정:                         ink_topics (day, word)
--   · 글 가리기:                                   ink_posts.hidden = true
--   · 사용자 쓰기 금지:                            ink_bans 에 user_id 추가
--   · 금칙어:                                      ink_banned_words

-- ─────────────────────────── 테이블 ───────────────────────────

create table if not exists public.ink_settings (
  id int primary key default 1 check (id = 1),
  cap int not null default 20 check (cap between 1 and 500),
  max_len int not null default 300 check (max_len between 10 and 2000),
  hide_after_reports int not null default 3 check (hide_after_reports >= 1),
  hall_includes_quotes boolean not null default true,
  topic_epoch date not null default date '2026-10-01'
);
insert into public.ink_settings (id) values (1) on conflict (id) do nothing;

create table if not exists public.ink_topics (
  day date primary key,
  word text not null check (char_length(word) between 1 and 40)
);

create table if not exists public.ink_topic_pool (
  id serial primary key,
  word text not null unique check (char_length(word) between 1 and 40)
);

create table if not exists public.ink_posts (
  id bigserial primary key,
  day date not null,
  slot int not null,
  user_id uuid not null,
  kind text not null default 'original' check (kind in ('original', 'quote')),
  body text,
  src_title text,
  src_author text,
  created_at timestamptz not null default now(),
  likes int not null default 0,
  reports int not null default 0,
  hidden boolean not null default false,
  deleted boolean not null default false,
  unique (day, slot),
  unique (day, user_id)
);
create index if not exists ink_posts_day_likes on public.ink_posts (day, likes desc);

create table if not exists public.ink_likes (
  post_id bigint not null references public.ink_posts (id) on delete cascade,
  user_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.ink_reports (
  post_id bigint not null references public.ink_posts (id) on delete cascade,
  user_id uuid not null,
  reason text not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.ink_bans (
  user_id uuid primary key,
  reason text,
  created_at timestamptz not null default now()
);

create table if not exists public.ink_banned_words (
  word text primary key
);

-- 앱(anon · authenticated)은 테이블을 직접 못 건드린다. 함수로만.
do $$
declare t text;
begin
  foreach t in array array['ink_settings','ink_topics','ink_topic_pool','ink_posts','ink_likes',
                           'ink_reports','ink_bans','ink_banned_words'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;
revoke all on all sequences in schema public from anon, authenticated;

-- ─────────────────────────── 글감 60개 (순서대로 돌아간다) ───────────────────────────

insert into public.ink_topic_pool (word) values
  ('파란 나무'), ('마지막 버스'), ('잠긴 서랍'), ('비 오는 옥상'), ('오래된 편지'),
  ('고양이의 비밀'), ('새벽 네 시'), ('잃어버린 우산'), ('빈 놀이터'), ('거울 속의 나'),
  ('첫눈'), ('낡은 카메라'), ('여름의 끝'), ('이름 없는 섬'), ('종이비행기'),
  ('붉은 달'), ('두 번째 기회'), ('창문 너머'), ('사라진 기차역'), ('오늘의 거짓말'),
  ('소금 맛 바람'), ('유리 정원'), ('열쇠 하나'), ('기억 상점'), ('밤의 도서관'),
  ('초록 우체통'), ('시간을 파는 가게'), ('무지개 계단'), ('모래시계'), ('이상한 초대장'),
  ('달리는 꿈'), ('겨울 바다'), ('노란 우산'), ('녹슨 자전거'), ('별이 떨어진 날'),
  ('비밀 지도'), ('마지막 한 조각'), ('잠들지 않는 도시'), ('오래된 약속'), ('하얀 거짓말'),
  ('구름 공장'), ('투명 인간'), ('늦은 답장'), ('이사 가는 날'), ('빈 의자'),
  ('목소리 없는 노래'), ('푸른 새벽'), ('등대지기'), ('반쪽짜리 편지'), ('미로'),
  ('첫 월급'), ('버려진 인형'), ('여우비'), ('뒤바뀐 이름'), ('불 꺼진 무대'),
  ('기차 창밖'), ('작은 용'), ('낯선 전화'), ('시계탑'), ('은하수 식당')
on conflict (word) do nothing;

insert into public.ink_banned_words (word) values
  ('시발'), ('씨발'), ('ㅅㅂ'), ('병신'), ('ㅂㅅ'), ('좆'), ('개새끼'), ('닥쳐'), ('꺼져'),
  ('섹스'), ('자살하'), ('죽어라'), ('카톡아이디'), ('오픈채팅'), ('텔레그램')
on conflict (word) do nothing;

-- ─────────────────────────── 도우미 (앱에서 직접 못 부름) ───────────────────────────

-- 테스트에서 시간을 바꿀 수 있게 'ink.fake_now' 설정을 본다. 운영에서는 항상 now().
create or replace function public.ink_now() returns timestamptz
language sql stable as $$
  select coalesce(nullif(current_setting('ink.fake_now', true), '')::timestamptz, now())
$$;

create or replace function public.ink_today() returns date
language sql stable as $$
  select (public.ink_now() at time zone 'Asia/Seoul')::date
$$;

-- 그날의 익명 이름 guest_0000 ~ guest_9999. 날마다 바뀐다.
create or replace function public.ink_nick(uid uuid, d date) returns text
language sql immutable as $$
  select 'guest_' || lpad((('x' || substr(md5(uid::text || ':' || d::text), 1, 8))::bit(32)::bigint % 10000)::text, 4, '0')
$$;

-- 차단용 작성자 표시. 날이 바뀌어도 같지만 user_id 를 알 수는 없다.
create or replace function public.ink_author(uid uuid) returns text
language sql immutable as $$
  select substr(md5('ink-author:' || uid::text), 1, 12)
$$;

create or replace function public.ink_topic(d date) returns text
language sql stable as $$
  select coalesce(
    (select word from public.ink_topics where day = d),
    (select p.word from public.ink_topic_pool p
      order by p.id
      offset (((d - (select topic_epoch from public.ink_settings where id = 1))
               % greatest((select count(*) from public.ink_topic_pool), 1))
              + greatest((select count(*) from public.ink_topic_pool), 1))
             % greatest((select count(*) from public.ink_topic_pool), 1)
      limit 1),
    '오늘')
$$;

create or replace function public.ink_seconds_left() returns int
language sql stable as $$
  select greatest(0, extract(epoch from (((public.ink_today() + 1)::timestamp at time zone 'Asia/Seoul') - public.ink_now()))::int)
$$;

create or replace function public.ink_post_json(p public.ink_posts, uid uuid) returns json
language sql stable as $$
  select json_build_object(
    'id', p.id,
    'day', p.day,
    'slot', p.slot,
    'nick', public.ink_nick(p.user_id, p.day),
    'author', public.ink_author(p.user_id),
    'kind', p.kind,
    'body', case when p.deleted then null
                 when p.hidden and p.user_id is distinct from uid then null
                 else p.body end,
    'src_title', case when p.deleted or (p.hidden and p.user_id is distinct from uid) then null else p.src_title end,
    'src_author', case when p.deleted or (p.hidden and p.user_id is distinct from uid) then null else p.src_author end,
    'likes', p.likes,
    'liked', coalesce(uid is not null and exists (select 1 from public.ink_likes l where l.post_id = p.id and l.user_id = uid), false),
    'mine', coalesce(p.user_id = uid, false),
    'hidden', p.hidden,
    'deleted', p.deleted,
    'time', to_char(p.created_at at time zone 'Asia/Seoul', 'HH24:MI')
  )
$$;

-- 명예의 전당 후보: 가려지거나 지워지지 않았고 +1 이 하나 이상. (hall_includes_quotes = false 면 인용글 제외)
create or replace function public.ink_hall_eligible(p public.ink_posts) returns boolean
language sql stable as $$
  select not p.hidden and not p.deleted and p.likes >= 1
     and (p.kind = 'original' or (select hall_includes_quotes from public.ink_settings where id = 1))
$$;

-- ─────────────────────────── 앱이 부르는 함수 ───────────────────────────

-- 게시판: 그날 글감 · 인원 · 글 목록. p_day 를 비우면 오늘.
create or replace function public.get_board(p_day date default null) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := ink_today();
  d date := least(coalesce(p_day, today), today);
  s ink_settings;
begin
  select * into s from ink_settings where id = 1;
  return json_build_object(
    'day', d,
    'is_today', d = today,
    'topic', ink_topic(d),
    'cap', s.cap,
    'max_len', s.max_len,
    'count', (select count(*) from ink_posts where day = d),
    'mine_slot', (select slot from ink_posts where day = d and user_id = uid),
    'banned', uid is not null and exists (select 1 from ink_bans where user_id = uid),
    'seconds_left', ink_seconds_left(),
    'posts', coalesce((select json_agg(ink_post_json(p, uid) order by p.slot) from ink_posts p where p.day = d), '[]'::json)
  );
end $$;

-- 위젯 · 공유용 요약 (로그인 없이도 부를 수 있다).
create or replace function public.board_status() returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'day', ink_today(),
    'topic', ink_topic(ink_today()),
    'cap', (select cap from ink_settings where id = 1),
    'count', (select count(*) from ink_posts where day = ink_today()),
    'seconds_left', ink_seconds_left()
  )
$$;

-- 글 올리기. 실패하면 'ink:<코드>' 예외: auth · banned · empty · too_long · link · word · source · already · full
create or replace function public.post_entry(p_body text, p_kind text default 'original',
                                             p_title text default null, p_author text default null)
returns json
language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  d date := ink_today();
  s ink_settings;
  b text;
  k text := coalesce(nullif(btrim(p_kind), ''), 'original');
  t text := nullif(btrim(coalesce(p_title, '')), '');
  a text := nullif(btrim(coalesce(p_author, '')), '');
  n int;
  new_id bigint;
begin
  if uid is null then raise exception 'ink:auth'; end if;
  if exists (select 1 from ink_bans where user_id = uid) then raise exception 'ink:banned'; end if;
  select * into s from ink_settings where id = 1;

  b := regexp_replace(coalesce(p_body, ''), E'\r\n?', E'\n', 'g');
  b := regexp_replace(b, E'[ \t]+\n', E'\n', 'g');
  b := regexp_replace(b, E'\n{3,}', E'\n\n', 'g');
  b := btrim(b, E' \t\n');
  if b = '' then raise exception 'ink:empty'; end if;
  if char_length(b) > s.max_len then raise exception 'ink:too_long'; end if;

  if k not in ('original', 'quote') then raise exception 'ink:source'; end if;
  if k = 'quote' then
    if t is null or a is null or char_length(t) > 60 or char_length(a) > 40 then
      raise exception 'ink:source';
    end if;
  else
    t := null; a := null;
  end if;

  if (b || ' ' || coalesce(t, '') || ' ' || coalesce(a, ''))
       ~* '(https?://|www\.|[a-z0-9-]+\.(com|net|org|kr|io|me|co|ly|gg|link)(/|\s|$))' then
    raise exception 'ink:link';
  end if;
  if exists (select 1 from ink_banned_words w
             where position(lower(w.word) in lower(regexp_replace(b || coalesce(t, '') || coalesce(a, ''), '\s', '', 'g'))) > 0) then
    raise exception 'ink:word';
  end if;

  -- 같은 날 동시에 들어온 요청은 한 줄로 세운다 (선착순).
  perform pg_advisory_xact_lock(hashtext('ink:' || d::text));
  if exists (select 1 from ink_posts where day = d and user_id = uid) then raise exception 'ink:already'; end if;
  select count(*) into n from ink_posts where day = d;
  if n >= s.cap then raise exception 'ink:full'; end if;

  insert into ink_posts (day, slot, user_id, kind, body, src_title, src_author, created_at)
  values (d, n + 1, uid, k, b, t, a, ink_now())
  returning id into new_id;

  return json_build_object('id', new_id, 'slot', n + 1, 'count', n + 1, 'cap', s.cap);
end $$;

-- +1 누르기 / 취소. 내 글에는 못 누른다.
create or replace function public.toggle_like(p_id bigint) returns json
language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p ink_posts;
  now_liked boolean;
begin
  if uid is null then raise exception 'ink:auth'; end if;
  select * into p from ink_posts where id = p_id for update;
  if not found or p.deleted or p.hidden then raise exception 'ink:not_found'; end if;
  if p.user_id = uid then raise exception 'ink:own'; end if;
  if exists (select 1 from ink_likes where post_id = p_id and user_id = uid) then
    delete from ink_likes where post_id = p_id and user_id = uid;
    now_liked := false;
  else
    insert into ink_likes (post_id, user_id) values (p_id, uid);
    now_liked := true;
  end if;
  update ink_posts set likes = (select count(*) from ink_likes where post_id = p_id) where id = p_id
  returning likes into p.likes;
  return json_build_object('id', p_id, 'likes', p.likes, 'liked', now_liked);
end $$;

-- 신고. 같은 글은 한 사람이 한 번. 쌓이면 자동으로 가린다.
create or replace function public.report_post(p_id bigint, p_reason text) returns json
language plpgsql volatile security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p ink_posts;
  r text := left(coalesce(nullif(btrim(p_reason), ''), 'etc'), 40);
begin
  if uid is null then raise exception 'ink:auth'; end if;
  select * into p from ink_posts where id = p_id for update;
  if not found then raise exception 'ink:not_found'; end if;
  if p.user_id = uid then raise exception 'ink:own'; end if;
  insert into ink_reports (post_id, user_id, reason) values (p_id, uid, r) on conflict do nothing;
  update ink_posts
     set reports = (select count(*) from ink_reports where post_id = p_id),
         hidden = hidden or (select count(*) from ink_reports where post_id = p_id)
                            >= (select hide_after_reports from ink_settings where id = 1)
   where id = p_id
  returning hidden into p.hidden;
  return json_build_object('id', p_id, 'hidden', p.hidden);
end $$;

-- 내 글 지우기. 자리는 그대로 찬 채로 남는다 (선착순 되돌리기 방지).
create or replace function public.delete_my_post(p_id bigint) returns json
language plpgsql volatile security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'ink:auth'; end if;
  update ink_posts set deleted = true, body = null, src_title = null, src_author = null
   where id = p_id and user_id = uid;
  if not found then raise exception 'ink:not_found'; end if;
  delete from ink_likes where post_id = p_id;
  update ink_posts set likes = 0 where id = p_id;
  return json_build_object('id', p_id, 'deleted', true);
end $$;

-- 내가 쓴 글 모아 보기 (최근 순).
create or replace function public.my_posts() returns json
language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return '[]'::json; end if;
  return coalesce((
    select json_agg(json_build_object(
      'id', p.id, 'day', p.day, 'topic', ink_topic(p.day), 'slot', p.slot, 'kind', p.kind,
      'body', p.body, 'src_title', p.src_title, 'src_author', p.src_author,
      'likes', p.likes, 'hidden', p.hidden, 'deleted', p.deleted) order by p.day desc)
    from ink_posts p where p.user_id = uid), '[]'::json);
end $$;

-- 명예의 전당.
--   month:     이번 달 (한국 시간) 어제까지 날마다 1위
--   today:     오늘 지금 1위 (아직 확정 아님)
--   champions: 지난달들의 '이달의 1위' 한 편씩 (최근 달부터)
create or replace function public.get_hall(p_months int default 24) returns json
language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := ink_today();
  month_start date := date_trunc('month', today)::date;
begin
  return json_build_object(
    'month_label', to_char(today, 'YYYY.MM'),
    'today', (
      select ink_post_json(p, uid)::jsonb || jsonb_build_object('topic', ink_topic(p.day))
        from ink_posts p
       where p.day = today and ink_hall_eligible(p)
       order by p.likes desc, p.slot asc limit 1),
    'month', coalesce((
      select json_agg(x.j order by x.day desc) from (
        select distinct on (p.day) p.day, ink_post_json(p, uid)::jsonb || jsonb_build_object('topic', ink_topic(p.day)) as j
          from ink_posts p
         where p.day >= month_start and p.day < today and ink_hall_eligible(p)
         order by p.day, p.likes desc, p.slot asc) x), '[]'::json),
    'champions', coalesce((
      select json_agg(x.j order by x.m desc) from (
        select distinct on (date_trunc('month', p.day)) date_trunc('month', p.day) as m,
               ink_post_json(p, uid)::jsonb || jsonb_build_object(
                 'topic', ink_topic(p.day), 'month', to_char(p.day, 'YYYY.MM')) as j
          from ink_posts p
         where p.day < month_start
           and p.day >= (month_start - make_interval(months => greatest(p_months, 1)))::date
           and ink_hall_eligible(p)
         order by date_trunc('month', p.day), p.likes desc, p.day asc, p.slot asc) x), '[]'::json)
  );
end $$;

-- ─────────────────────────── 권한 ───────────────────────────

revoke execute on function
  public.ink_now(), public.ink_today(), public.ink_nick(uuid, date), public.ink_author(uuid),
  public.ink_topic(date), public.ink_seconds_left(), public.ink_post_json(public.ink_posts, uuid),
  public.ink_hall_eligible(public.ink_posts),
  public.get_board(date), public.board_status(), public.post_entry(text, text, text, text),
  public.toggle_like(bigint), public.report_post(bigint, text), public.delete_my_post(bigint),
  public.my_posts(), public.get_hall(int)
from public, anon, authenticated;

grant execute on function public.get_board(date), public.board_status(), public.get_hall(int)
  to anon, authenticated;
grant execute on function public.post_entry(text, text, text, text), public.toggle_like(bigint),
  public.report_post(bigint, text), public.delete_my_post(bigint), public.my_posts()
  to authenticated;
