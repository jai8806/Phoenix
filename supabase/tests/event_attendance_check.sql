-- Plays through an event roll-call. Run after 00_auth_stub.sql and all migrations.
insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Demo');
insert into units (id, institution_id, name, wing) values
 ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Unit A','army'),
 ('00000000-0000-0000-0000-0000000000b2','00000000-0000-0000-0000-0000000000a1','Unit B','army');
insert into auth.users (id, email) values
 ('00000000-0000-0000-0000-000000000001','ano@a'), ('00000000-0000-0000-0000-000000000002','c1@a'),
 ('00000000-0000-0000-0000-000000000003','c2@a'), ('00000000-0000-0000-0000-000000000004','c@b');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1', role='ano' where id='00000000-0000-0000-0000-000000000001';
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1' where id in ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b2' where id='00000000-0000-0000-0000-000000000004';
grant usage on schema public, auth to authenticated; grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated; grant execute on all functions in schema public, auth to authenticated;
set role authenticated;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
insert into calendar_events (id, unit_id, title, kind, starts_at, needs_response, details) values
 ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000b1','Saturday parade','parade', now() + interval '2 days', true, 'Report 0730 in full uniform'),
 ('00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000b1','Past parade','parade', now() - interval '1 day', true, null),
 ('00000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000b1','Info only','event', now() + interval '2 days', false, null);

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- cadet 1: coming, then changes to absent without a reason (error), then with one:'
select respond_to_event('00000000-0000-0000-0000-0000000000e1', 'coming');
select respond_to_event('00000000-0000-0000-0000-0000000000e1', 'absent', '');
select respond_to_event('00000000-0000-0000-0000-0000000000e1', 'absent', 'University exam that day');
\echo '--- after the deadline (expect closed), on an info-only event (expect error):'
select respond_to_event('00000000-0000-0000-0000-0000000000e2', 'coming');
select respond_to_event('00000000-0000-0000-0000-0000000000e3', 'coming');
\echo '--- cadet 1 cannot mark themselves attended (expect 0 rows changed):'
update event_responses set attended = true where cadet_id = auth.uid();
select status, reason, attended from event_responses;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000003';
select respond_to_event('00000000-0000-0000-0000-0000000000e1', 'coming');
\echo '--- cadet 2 sees only their own response (expect 1):'
select count(*) from event_responses;

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000004';
\echo '--- cadet from another unit (expect not found):'
select respond_to_event('00000000-0000-0000-0000-0000000000e1', 'coming');

set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
\echo '--- ANO sees both and marks cadet 2 attended (expect coming 1, absent 1 with reason, attended true):'
update event_responses set attended = true, marked_by = auth.uid(), marked_at = now()
  where event_id = '00000000-0000-0000-0000-0000000000e1' and cadet_id = '00000000-0000-0000-0000-000000000003';
select status, reason, attended from event_responses order by status;
reset role;
