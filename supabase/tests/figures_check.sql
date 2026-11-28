insert into institutions (id, name) values ('00000000-0000-0000-0000-0000000000a1', 'Demo');
insert into units (id, institution_id, name, wing) values ('00000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000a1','Unit A','army');
insert into auth.users (id, email) values ('00000000-0000-0000-0000-000000000002','c@a'),('00000000-0000-0000-0000-000000000009','x@x');
update profiles set unit_id='00000000-0000-0000-0000-0000000000b1' where id='00000000-0000-0000-0000-000000000002';
insert into storage.objects (bucket_id, name) values ('precis-figures', 'army_sd_sw_2025/x.webp');
grant usage on schema public, storage, auth to authenticated; grant select on all tables in schema public, storage to authenticated; grant execute on all functions in schema public, auth to authenticated;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';
\echo '--- unit member: figures rows and files visible (expect >0, 1):'
select count(*) from figures; select count(*) from storage.objects;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000009';
\echo '--- signed in, no unit: nothing (expect 0, 0):'
select count(*) from figures; select count(*) from storage.objects;
set request.jwt.claim.sub = '';
\echo '--- anonymous: nothing (expect 0, 0):'
select count(*) from figures; select count(*) from storage.objects;
