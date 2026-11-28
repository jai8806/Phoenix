-- Plays through appointments, mock drafts and anonymous queries.
-- Run after 00_auth_stub.sql and all migrations.
insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Demo');
insert into units (id, institution_id, name, wing) values
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Unit A','army'),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a1','Unit B','army');
-- 1 ANO, 2 CSUO, 3 JUO, 4 cadet, 5 cadet in unit B, 6 senior cadet with no appointment
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001','ano@a'), ('00000000-0000-0000-0000-000000000002','csuo@a'),
 ('00000000-0000-0000-0000-000000000003','juo@a'), ('00000000-0000-0000-0000-000000000004','c@a'),
 ('00000000-0000-0000-0000-000000000005','c@b'), ('00000000-0000-0000-0000-000000000006','sgt@a');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='ano' where id='00000000-0000-0000-0000-000000000001';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='senior_cadet', appointment='csuo' where id='00000000-0000-0000-0000-000000000002';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='senior_cadet', appointment='juo' where id='00000000-0000-0000-0000-000000000003';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1' where id='00000000-0000-0000-0000-000000000004';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b2' where id='00000000-0000-0000-0000-000000000005';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='senior_cadet' where id='00000000-0000-0000-0000-000000000006';
\echo '--- an appointment on a plain cadet is refused (expect check violation):'
update profiles set appointment='csm' where id='00000000-0000-0000-0000-000000000004';
insert into questions (id, unit_id, subject, prompt, options, correct_index, status) values
 ('00000000-0000-0000-0000-0000000000f1', null, 'Map Reading', 'Q1?', array['a','b','c','d'], 0, 'approved'),
 ('00000000-0000-0000-0000-0000000000f2', null, 'Map Reading', 'Q2?', array['a','b','c','d'], 1, 'approved'),
 ('00000000-0000-0000-0000-0000000000f3', '00000000-0000-0000-0000-0000000000b2', 'Map Reading', 'Unit B only', array['a','b','c','d'], 1, 'approved');
grant usage on schema public, auth to authenticated; grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated; grant execute on all functions in schema public, auth to authenticated;
set role authenticated;

-- ===== Appointments
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- CSUO promotes the cadet to senior cadet + CSM (expect UPDATE 1):'
update profiles set role='senior_cadet', appointment='csm' where id='00000000-0000-0000-0000-000000000004';
\echo '--- CSUO cannot touch the ANO or make anyone ANO (expect UPDATE 0, then error):'
update profiles set rank='X' where id='00000000-0000-0000-0000-000000000001';
update profiles set role='ano', appointment=null where id='00000000-0000-0000-0000-000000000004';
\echo '--- CSUO cannot change their own appointment (expect error):'
update profiles set appointment='suo' where id='00000000-0000-0000-0000-000000000002';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- JUO cannot change the roster (expect UPDATE 0):'
update profiles set role='cadet', appointment=null where id='00000000-0000-0000-0000-000000000004';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
update profiles set role='cadet', appointment=null where id='00000000-0000-0000-0000-000000000004';
select full_name, role, appointment from profiles where unit_id='00000000-0000-0000-0000-0000000000b1' order by full_name;

-- ===== Mock drafts
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- JUO builds a draft (expect 1 test, 2 questions):'
insert into tests (id, unit_id, title, duration_minutes, mode, pattern, is_draft) values
 ('00000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000b1','Mock 1',180,'omr','bcert',true);
select set_test_questions('00000000-0000-0000-0000-0000000000d1', array['00000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f2']::uuid[], array[1,5]);
select position from test_questions where test_id='00000000-0000-0000-0000-0000000000d1' order by position;
\echo '--- a question from another unit is refused (expect Unknown question):'
select set_test_questions('00000000-0000-0000-0000-0000000000d1', array['00000000-0000-0000-0000-0000000000f3']::uuid[], array[1]);
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- cadet cannot see the draft or sit it (expect 0, then not published / not found):'
select count(*) from tests;
select submit_attempt('00000000-0000-0000-0000-0000000000d1', '{}'::jsonb);
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- JUO cannot publish (expect error):'
update tests set is_draft=false where id='00000000-0000-0000-0000-0000000000d1';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- CSUO publishes (expect UPDATE 1, published_by = CSUO):'
update tests set is_draft=false, opens_at=now() + interval '1 day' where id='00000000-0000-0000-0000-0000000000d1';
select is_draft, published_by = auth.uid() as by_me from tests;
\echo '--- and it cannot go back to draft (expect error):'
update tests set is_draft=true where id='00000000-0000-0000-0000-0000000000d1';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- now the cadet sees it (expect 1):'
select count(*) from tests;

-- ===== Anonymous queries
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- cadet asks two queries; the second lets JUO/CSM/CQMS see it too:'
select ask_query('ticket-aaaaaaaaaaaaaaaaaaaaaaaa', 'Seniors shouting at camp', 'During the last camp some seniors...', 'camp', 'command') is not null as asked1;
select ask_query('ticket-bbbbbbbbbbbbbbbbbbbbbbbb', 'Doubt about B cert dates', 'When is the B certificate exam?', 'studies', 'seniors') is not null as asked2;
\echo '--- nothing in the tables names the cadet (expect no rows readable by the cadet):'
select count(*) from queries;
\echo '--- the cadet sees both through their ticket codes (expect 2):'
select subject, status, jsonb_array_length(messages) from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa','ticket-bbbbbbbbbbbbbbbbbbbbbbbb']);
\echo '--- a short ticket is refused:'
select ask_query('short', 'Hello there', 'Something long enough');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- the ANO sees no queries (expect 0, 0) and cannot reply (expect not found):'
select count(*) from queries;
select count(*) from query_messages;
select add_query_message((select id from queries limit 1), 'hi');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- JUO sees only the one opened to seniors (expect 1: Doubt about B cert dates):'
select subject from queries;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000006';
\echo '--- a senior cadet without an appointment sees none (expect 0):'
select count(*) from queries;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- CSUO sees both, replies, raises one with the ANO:'
select subject, audience, status from queries order by subject;
select add_query_message(id, 'We will look into it. Can you tell us which day?') from queries where subject like 'Seniors%';
select set_query_status(id, 'escalated') from queries where subject like 'Seniors%';
select q.subject, q.status, m.from_senior, m.senior_label, m.senior_id = auth.uid() as by_me from queries q join query_messages m on m.query_id = q.id order by q.subject, m.created_at, m.from_senior;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- the cadet sees the reply labelled CSUO, follows up, closes the other:'
select subject, status, messages -> 1 ->> 'senior_label' as replied_by from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa']);
select add_query_message(id, 'It was on day 3.', 'ticket-aaaaaaaaaaaaaaaaaaaaaaaa') from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa']);
select set_query_status(id, 'closed', 'ticket-bbbbbbbbbbbbbbbbbbbbbbbb') from my_queries(array['ticket-bbbbbbbbbbbbbbbbbbbbbbbb']);
select subject, status, jsonb_array_length(messages) from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa','ticket-bbbbbbbbbbbbbbbbbbbbbbbb']) order by subject;
\echo '--- a wrong ticket gets nothing, and cannot post (expect 0 rows, then not found):'
select count(*) from my_queries(array['ticket-cccccccccccccccccccccccc']);
select add_query_message((select id from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa'])), 'x', 'ticket-cccccccccccccccccccccccc');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000005';
\echo '--- a cadet in another unit with the right ticket still gets nothing (expect 0):'
select count(*) from my_queries(array['ticket-aaaaaaaaaaaaaaaaaaaaaaaa']);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- daily limit: 3 more are fine, the 6th is refused:'
select ask_query('ticket-d1aaaaaaaaaaaaaaaaaaaaaaa', 'Extra one', 'Some text here');
select ask_query('ticket-d2aaaaaaaaaaaaaaaaaaaaaaa', 'Extra two', 'Some text here');
select ask_query('ticket-d3aaaaaaaaaaaaaaaaaaaaaaa', 'Extra three', 'Some text here');
select ask_query('ticket-d4aaaaaaaaaaaaaaaaaaaaaaa', 'Extra four', 'Some text here');
\echo '--- the cadet cannot read the quota table (expect 0):'
select count(*) from query_quota;
reset role;
