-- Run after 00_auth_stub.sql and all migrations on a fresh database.
insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Demo');
insert into units (id, institution_id, name, wing) values
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Unit A','army'),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a1','Unit B','army');
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001','ano@a'), ('00000000-0000-0000-0000-000000000002','c@a'),
 ('00000000-0000-0000-0000-000000000003','c@b');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='ano' where id='00000000-0000-0000-0000-000000000001';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1' where id='00000000-0000-0000-0000-000000000002';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b2' where id='00000000-0000-0000-0000-000000000003';
insert into questions (id, unit_id, subject, prompt, options, correct_index, status) values
 ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-0000000000b1', 'Drill', 'Q1?', array['a','b','c','d'], 1, 'approved'),
 ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-0000000000b1', 'Drill', 'Q2?', array['a','b','c','d'], 2, 'approved'),
 ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-0000000000b1', 'Drill', 'Q3?', array['a','b','c','d'], 0, 'approved');
grant usage on schema public, auth to authenticated; grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated; grant execute on all functions in schema public, auth to authenticated;
set role authenticated;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- ANO creates a test with 3 questions (+2 / -0.5):'
insert into tests (id, unit_id, title, duration_minutes, marks_correct, marks_wrong, created_by)
values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1', 'Drill check', 10, 2, 0.5,
        '00000000-0000-0000-0000-000000000001');
insert into test_questions (test_id, question_id, position) values
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-00000000c001',1),
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-00000000c002',2),
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-00000000c003',3);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- cadet: one right, one wrong, one skipped (expect 1.5):'
select submit_attempt('00000000-0000-0000-0000-0000000000e1',
  '{"00000000-0000-0000-0000-00000000c001": 1, "00000000-0000-0000-0000-00000000c002": 0}'::jsonb);
\echo '--- second attempt (expect error):'
select submit_attempt('00000000-0000-0000-0000-0000000000e1', '{}'::jsonb);
\echo '--- cadet tries to rewrite their score or insert a fake attempt (expect no change / error):'
update test_attempts set score = 999 where cadet_id = auth.uid();
select score from test_attempts where cadet_id = auth.uid();
insert into test_attempts (test_id, cadet_id, score) values ('00000000-0000-0000-0000-0000000000e1', auth.uid(), 350);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- cadet from another unit cannot see or take it (expect 0, then error):'
select count(*) from tests;
select submit_attempt('00000000-0000-0000-0000-0000000000e1', '{}'::jsonb);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- ANO sees the attempt and the answers (expect 1.5 and 3 answers):'
select score from test_attempts;
select count(*) from attempt_answers;
