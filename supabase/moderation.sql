-- 신고 처리 (애플 규칙: 신고는 24시간 안에 확인해 글을 지우고 쓴 사람을 내보낸다)
-- Supabase → SQL Editor 에 붙여 넣고 필요한 부분만 골라 Run.

-- ① 신고 들어온 글 (최근 신고 순). 아직 처리 안 한 것만 보려면 맨 아래 줄의 주석(--)을 지운다.
select p.id, p.day, p.slot, p.reports, p.hidden,
       left(p.body, 80) as body,
       string_agg(distinct r.reason, ', ') as reasons,
       max(r.created_at) as last_report,
       exists (select 1 from ink_bans b where b.user_id = p.user_id or b.device = p.device) as banned
from ink_posts p
join ink_reports r on r.post_id = p.id
where not p.deleted
group by p.id
-- having not bool_or(p.hidden)
order by last_report desc
limit 50;

-- ② 규칙을 어긴 글: 숨기고(모두에게 가려짐) 쓴 사람(기기까지) 쓰기를 영구히 막는다.
--    123 을 ①에서 본 글 id 로 바꿔서 Run.
with target as (select user_id, device from ink_posts where id = 123)
insert into ink_bans (user_id, reason, device)
select user_id, 'report', device from target
on conflict (user_id) do update set device = excluded.device, reason = excluded.reason;
update ink_posts set hidden = true where id = 123;

-- ③ 문제 없는 글이었다면 다시 보이게 (신고로 잘못 가려졌을 때)
-- update ink_posts set hidden = false where id = 123;
