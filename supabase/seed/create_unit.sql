-- Create your institution and unit. Edit the four values marked EDIT, then
-- run this in the Supabase SQL Editor. It prints the unit's join code: share
-- it with your cadets so they can join from the app.

with inst as (
  insert into institutions (name, city)
  values ('Your College Name', 'Your City')            -- EDIT: institution name and city
  returning id
)
insert into units (institution_id, name, wing, directorate)
select id,
       '1 Bn NCC',                                     -- EDIT: unit name, e.g. "1 KAR BN NCC"
       'army',                                          -- EDIT: army | navy | air | rvc
       'Your Directorate'                               -- EDIT: e.g. "Karnataka & Goa"
from inst
returning name, join_code;


-- After the ANO has created an account in the app (and confirmed their
-- email), make them the unit's ANO. Replace the email address and run:
--
-- update profiles
-- set role = 'ano',
--     unit_id = (select id from units where name = '1 Bn NCC'),   -- same unit name as above
--     rank = 'Lt'                                                  -- the ANO's rank
-- where id = (select id from auth.users where email = 'ano@example.com');
--
-- Senior cadets join with the code like everyone else; the ANO then promotes
-- them (role 'senior_cadet') from the database until the Command Center gets a
-- roles screen.
