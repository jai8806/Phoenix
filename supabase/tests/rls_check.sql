-- Run after the migrations on a scratch database (see supabase/README.md).
-- Each step prints what to expect next to the actual result.
grant usage on schema public, auth to authenticated;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;
grant execute on all functions in schema public, auth to authenticated;

insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Demo College');
insert into units (id, institution_id, name, wing, join_code) values
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Unit A','army','JOINA'),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a1','Unit B','navy','JOINB');
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001','ano@a'),('00000000-0000-0000-0000-000000000002','cadet@a'),
 ('00000000-0000-0000-0000-000000000003','cadet@b'),('00000000-0000-0000-0000-000000000004','suo@a');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='ano' where id='00000000-0000-0000-0000-000000000001';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='senior_cadet' where id='00000000-0000-0000-0000-000000000004';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b2' where id='00000000-0000-0000-0000-000000000003';
insert into announcements (unit_id, author_id, title, body) values
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-000000000003','B only','x');
\echo '--- trigger created profiles (expect 4):'
select count(*) from profiles;

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- new cadet joins unit A by code (expect t):'
select join_unit('joina') is not null as joined;
\echo '--- cadet A sees unit B announcement? (expect 0):'
select count(*) from announcements;
\echo '--- cadet A tries to post (expect RLS error):'
insert into announcements (unit_id, author_id, title, body) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000002','hack','x');
\echo '--- cadet A tries to promote self (expect error, role stays cadet):'
update profiles set role='ano' where id='00000000-0000-0000-0000-000000000002';
select role from profiles where id='00000000-0000-0000-0000-000000000002';
\echo '--- cadet writes one private and one shared diary entry:'
insert into diary_entries (cadet_id, session_type, metrics) values ('00000000-0000-0000-0000-000000000002','shooting','{"score":44}');
insert into diary_entries (cadet_id, session_type, visibility) values ('00000000-0000-0000-0000-000000000002','pt','shared_with_unit');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- senior cadet posts announcement (expect ok):'
insert into announcements (unit_id, author_id, title, body) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-000000000004','Parade','Sat');
\echo '--- senior cadet tries to promote self to ano (expect error, role stays senior_cadet):'
update profiles set role='ano' where id='00000000-0000-0000-0000-000000000004';
select role from profiles where id='00000000-0000-0000-0000-000000000004';
\echo '--- senior cadet reads the cadet diary (expect 0: only the ANO sees shared entries):'
select count(*) from diary_entries;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- ANO sees diary entries (expect only pt / shared_with_unit):'
select session_type, visibility from diary_entries;
\echo '--- ANO promotes the cadet to senior_cadet (expect senior_cadet):'
update profiles set role='senior_cadet' where id='00000000-0000-0000-0000-000000000002';
select role from profiles where id='00000000-0000-0000-0000-000000000002';

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- unit B cadet: announcements visible (expect only "B only"):'
select title from announcements;
\echo '--- unit B cadet tries to join unit A while already in B (expect error, unit stays Unit B):'
select join_unit('JOINA');
select u.name from profiles p join units u on u.id = p.unit_id where p.id = auth.uid();

-- Knowledge base (run tools/ingest/to_sql.py output first for non-zero counts).
set request.jwt.claim.sub = '';
\echo '--- anonymous visitor reads précis passages (expect 0):'
select count(*) from document_chunks;
select count(*) from search_chunks('supreme commander armed forces');
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
\echo '--- cadet in a unit searches the précis (expect matches, best first):'
select document_title, heading, page from search_chunks('Who is the supreme commander of the armed forces?', 2);
\echo '--- cadet sees draft questions? (expect 0: drafts are admin-only):'
select count(*) from questions where status = 'draft';
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- ANO sees draft questions (expect > 0 after a load):'
select count(*) from questions where status = 'draft';
