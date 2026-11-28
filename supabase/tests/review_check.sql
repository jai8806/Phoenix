-- Run after rls_check.sql (it reuses its users and units) and a précis load.
-- Each step prints what to expect.
set role authenticated;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- plain cadet, unit B
\echo '--- cadet sees review queue (expect 0):'
select count(*) from review_queue();
\echo '--- cadet tries to approve (expect error):'
select adopt_question((select id from questions limit 1), 0::smallint);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';  -- ANO, unit A
\echo '--- ANO: drafts awaiting review (expect all drafts, e.g. 232; review_queue() returns at most 200 at a time):'
select count(*) from questions q where q.unit_id is null and q.status = 'draft'
  and not exists (select 1 from questions a where a.unit_id = my_unit_id() and a.adopted_from = q.id);
\echo '--- ANO approves one with answer (b) (expect a uuid):'
select adopt_question((select id from review_queue(1)), 1::smallint) is not null as approved;
\echo '--- awaiting review shrinks by one (e.g. 231); approved copy is visible to the unit:'
select count(*) from questions q where q.unit_id is null and q.status = 'draft'
  and not exists (select 1 from questions a where a.unit_id = my_unit_id() and a.adopted_from = q.id);
select status, correct_index, adopted_from is not null as adopted, unit_id is not null as in_unit from questions where unit_id = my_unit_id();
\echo '--- approving the same question again updates, not duplicates (expect 1 row, answer 2):'
select adopt_question((select adopted_from from questions where unit_id = my_unit_id() limit 1), 2::smallint) is not null;
select count(*), max(correct_index) from questions where unit_id = my_unit_id();
\echo '--- out-of-range answer (expect error):'
select adopt_question((select id from review_queue(1)), 9::smallint);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';  -- cadet in unit B
\echo '--- unit B cadet sees unit A approved question? (expect 0):'
select count(*) from questions where status = 'approved';

\echo '--- Ustaad log: cadet writes own row, cannot write for others (expect 1 then error):'
insert into ustaad_log (user_id, question, answered) values ('00000000-0000-0000-0000-000000000003', 'q', true);
select count(*) from ustaad_log;
insert into ustaad_log (user_id, question, answered) values ('00000000-0000-0000-0000-000000000001', 'q', true);
