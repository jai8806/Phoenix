-- Plays through an OMR mock. Run after 00_auth_stub.sql and all migrations.
\set ON_ERROR_STOP 0
\set QUIET 1
\pset footer off

insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Test College');
insert into units (id, institution_id, name, wing) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000a1', 'Unit One', 'army');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'ano@x'), ('00000000-0000-0000-0000-0000000000c2', 'cdt@x');
update profiles set unit_id = '00000000-0000-0000-0000-0000000000b1', role = 'ano' where id = '00000000-0000-0000-0000-0000000000c1';
update profiles set unit_id = '00000000-0000-0000-0000-0000000000b1' where id = '00000000-0000-0000-0000-0000000000c2';

grant usage on schema public, auth, storage to authenticated; grant all on all tables in schema public, storage to authenticated;
grant all on all sequences in schema public to authenticated; grant execute on all functions in schema public, auth to authenticated;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
insert into questions (id, unit_id, subject, prompt, options, correct_index, status) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', 'S', 'Q1', array['a','b','c','d'], 1, 'approved'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000b1', 'S', 'Q2', array['a','b','c','d'], 2, 'approved'),
  ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000b1', 'S', 'Q3', array['a','b','c','d'], 0, 'approved');
insert into tests (id, unit_id, title, duration_minutes, marks_correct, marks_wrong, mode, pattern, sheet_code, set_seed)
  values ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1', 'Mock 1', 180, 2, 0.5, 'omr', 'bcert', 4242, 7);
insert into test_questions (test_id, question_id, position) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d1', 1),
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d2', 2),
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000d3', 3);

set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';
\echo '--- cadet submits before the ANO starts (expect: not started yet):'
select submit_attempt('00000000-0000-0000-0000-0000000000e1', '{}'::jsonb);

set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
update tests set started_at = now(), opens_at = now(), closes_at = now() + interval '200 minutes'
  where id = '00000000-0000-0000-0000-0000000000e1';

set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';
\echo '--- cadet uploads someone else''s sheet path (expect: not yours):'
select submit_attempt('00000000-0000-0000-0000-0000000000e1', '{}'::jsonb, 0,
  '00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000000e1/00000000-0000-0000-0000-0000000000c1.jpg');
\echo '--- right, double-marked (-1), right: expect 2 - 0.5 + 2 = 3.5'
select submit_attempt('00000000-0000-0000-0000-0000000000e1',
  '{"00000000-0000-0000-0000-0000000000d1": 1, "00000000-0000-0000-0000-0000000000d2": -1, "00000000-0000-0000-0000-0000000000d3": 0}'::jsonb,
  1, '00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000000e1/00000000-0000-0000-0000-0000000000c2.jpg', 'A2', 3, 1);
\echo '--- the attempt keeps the sheet details (expect A2, 3 flags, 1 corrected):'
select score, set_label, scan_flags, corrected, sheet_path like '%c2.jpg' as own_photo from test_attempts;
\echo '--- storage: cadet uploads own sheet (ok), someone else''s (expect RLS error):'
insert into storage.objects (bucket_id, name) values ('omr-sheets', '00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000000e1/00000000-0000-0000-0000-0000000000c2.jpg');
insert into storage.objects (bucket_id, name) values ('omr-sheets', '00000000-0000-0000-0000-0000000000b1/00000000-0000-0000-0000-0000000000e1/00000000-0000-0000-0000-0000000000c1.jpg');
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';
\echo '--- ANO sees the cadet sheet (expect 1):'
select count(*) from storage.objects where bucket_id = 'omr-sheets';
reset role;
