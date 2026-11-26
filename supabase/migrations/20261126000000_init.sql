-- Phoenix: initial schema (Phase 0)
-- Multi-tenant: institution -> unit -> people. Every row a cadet can see is
-- scoped to their unit through row-level security (RLS).

create extension if not exists vector;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type app_role as enum ('cadet', 'senior_cadet', 'ano');
create type wing as enum ('army', 'navy', 'air', 'rvc');
create type division as enum ('jd', 'jw', 'sd', 'sw');
create type session_type as enum (
  'drill', 'shooting', 'pt', 'map_reading', 'obstacle', 'cultural', 'other'
);
create type diary_visibility as enum ('private', 'shared_with_unit');

-- ---------------------------------------------------------------------------
-- Organisation
-- ---------------------------------------------------------------------------
create table institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  created_at timestamptz not null default now()
);

create table units (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references institutions (id) on delete cascade,
  name text not null,                -- e.g. "1 KAR BN NCC"
  wing wing not null,
  directorate text,                  -- e.g. "Karnataka & Goa"
  join_code text not null unique default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_at timestamptz not null default now()
);

create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  unit_id uuid references units (id) on delete set null,
  role app_role not null default 'cadet',
  full_name text not null,
  regimental_no text,
  rank text,                         -- e.g. "CDT", "LCPL", "SUO"
  wing wing,
  division division,
  training_year smallint check (training_year between 1 and 3),
  date_of_birth date,                -- needed to know if guardian consent is required
  guardian_consent_at timestamptz,   -- DPDP Act: required for under-18 cadets
  created_at timestamptz not null default now()
);

-- Helpers used by RLS policies. SECURITY DEFINER so they can read profiles
-- without recursing through profiles' own policies.
create or replace function public.my_unit_id() returns uuid
language sql stable security definer set search_path = public as $$
  select unit_id from profiles where id = auth.uid()
$$;

create or replace function public.my_role() returns app_role
language sql stable security definer set search_path = public as $$
  select role from profiles where id = auth.uid()
$$;

create or replace function public.is_unit_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() in ('senior_cadet', 'ano'), false)
$$;

-- ---------------------------------------------------------------------------
-- Communication: announcements and academic calendar
-- ---------------------------------------------------------------------------
create table announcements (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units (id) on delete cascade,
  author_id uuid not null references profiles (id),
  title text not null,
  body text not null,
  pinned boolean not null default false,
  created_at timestamptz not null default now()
);

create table calendar_events (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units (id) on delete cascade,
  title text not null,
  kind text not null check (kind in ('parade', 'camp', 'exam', 'test', 'event')),
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Attendance (feeds the B/C certificate eligibility tracker)
-- ---------------------------------------------------------------------------
create table attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units (id) on delete cascade,
  event_id uuid references calendar_events (id) on delete set null,
  held_on date not null,
  periods smallint not null default 1, -- training periods counted for this session
  created_by uuid references profiles (id)
);

create table attendance_records (
  session_id uuid not null references attendance_sessions (id) on delete cascade,
  cadet_id uuid not null references profiles (id) on delete cascade,
  present boolean not null,
  primary key (session_id, cadet_id)
);

create table camp_records (
  id uuid primary key default gen_random_uuid(),
  cadet_id uuid not null references profiles (id) on delete cascade,
  camp_type text not null,           -- ATC, CATC, RDC, TSC, NSC, VSC, IDSSC...
  started_on date,
  ended_on date,
  verified_by uuid references profiles (id)
);

-- ---------------------------------------------------------------------------
-- Knowledge base for Ustaad (RAG)
-- ---------------------------------------------------------------------------
create table documents (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units (id) on delete cascade, -- null = shared official syllabus
  title text not null,
  subject text,
  wing wing,
  division_level text check (division_level in ('junior', 'senior')),
  storage_path text not null,
  source_url text,
  uploaded_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table document_chunks (
  id bigserial primary key,
  document_id uuid not null references documents (id) on delete cascade,
  page smallint,
  heading text,
  content text not null,
  embedding vector(1024),            -- bge-m3 / voyage multilingual dimension
  fts tsvector generated always as (to_tsvector('simple', content)) stored
);
create index on document_chunks using hnsw (embedding vector_cosine_ops);
create index on document_chunks using gin (fts);

-- ---------------------------------------------------------------------------
-- Question bank, tests and attempts
-- ---------------------------------------------------------------------------
create table questions (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid references units (id) on delete cascade, -- null = shared bank
  subject text not null,
  wing wing,                         -- null = common subject
  prompt text not null,
  options text[] not null check (array_length(options, 1) between 2 and 6),
  correct_index smallint not null,
  explanation text,
  source_chunk_id bigint references document_chunks (id) on delete set null,
  status text not null default 'approved' check (status in ('draft', 'approved')),
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table tests (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units (id) on delete cascade,
  title text not null,
  duration_minutes int not null,
  marks_correct numeric not null default 2,
  marks_wrong numeric not null default 0, -- negative marking, stored as positive value
  opens_at timestamptz,
  closes_at timestamptz,
  shuffle boolean not null default true,
  created_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table test_questions (
  test_id uuid not null references tests (id) on delete cascade,
  question_id uuid not null references questions (id) on delete cascade,
  position int not null,
  primary key (test_id, question_id)
);

create table test_attempts (
  id uuid primary key default gen_random_uuid(),
  test_id uuid not null references tests (id) on delete cascade,
  cadet_id uuid not null references profiles (id) on delete cascade,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  score numeric,
  focus_lost_count int not null default 0
);

create table attempt_answers (
  attempt_id uuid not null references test_attempts (id) on delete cascade,
  question_id uuid not null references questions (id) on delete cascade,
  chosen_index smallint,
  primary key (attempt_id, question_id)
);

-- ---------------------------------------------------------------------------
-- Training diary (private by default)
-- ---------------------------------------------------------------------------
create table diary_entries (
  id uuid primary key default gen_random_uuid(),
  cadet_id uuid not null references profiles (id) on delete cascade,
  session_type session_type not null,
  happened_on date not null default current_date,
  duration_minutes int,
  went_well text,
  to_improve text,
  instructor_notes text,
  mood smallint check (mood between 1 and 5),
  fatigue smallint check (fatigue between 1 and 5),
  sleep_hours numeric(3, 1),
  metrics jsonb not null default '{}'::jsonb, -- e.g. shooting: rifle, position, distance_m, rounds, score, group_mm
  target_photo_path text,
  visibility diary_visibility not null default 'private',
  created_at timestamptz not null default now()
);
create index on diary_entries (cadet_id, happened_on desc);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table institutions enable row level security;
alter table units enable row level security;
alter table profiles enable row level security;
alter table announcements enable row level security;
alter table calendar_events enable row level security;
alter table attendance_sessions enable row level security;
alter table attendance_records enable row level security;
alter table camp_records enable row level security;
alter table documents enable row level security;
alter table document_chunks enable row level security;
alter table questions enable row level security;
alter table tests enable row level security;
alter table test_questions enable row level security;
alter table test_attempts enable row level security;
alter table attempt_answers enable row level security;
alter table diary_entries enable row level security;

create policy "see own unit" on units for select using (id = my_unit_id());
create policy "see own institution" on institutions for select
  using (id in (select institution_id from units where id = my_unit_id()));

create policy "see self and unit mates" on profiles for select
  using (id = auth.uid() or unit_id = my_unit_id());
create policy "edit self" on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and role = my_role() and unit_id is not distinct from my_unit_id());
-- Only the ANO can change other people's role, rank or unit membership.
create policy "ano manages unit profiles" on profiles for update
  using (my_role() = 'ano' and unit_id = my_unit_id())
  with check (my_role() = 'ano' and (unit_id = my_unit_id() or unit_id is null));

-- Every new auth user gets a cadet profile with no unit.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- A cadet joins their unit with the code the ANO shares. Joining always
-- makes you a cadet; only the ANO can promote.
create or replace function public.join_unit(code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare target uuid;
begin
  select id into target from units where join_code = upper(trim(code));
  if target is null then raise exception 'Unknown unit code'; end if;
  update profiles set unit_id = target, role = 'cadet'
    where id = auth.uid() and unit_id is null;
  if not found then raise exception 'You already belong to a unit. Ask your ANO to move you.'; end if;
  return target;
end $$;

-- Unit-scoped content: everyone in the unit reads, admins write.
create policy "unit read" on announcements for select using (unit_id = my_unit_id());
create policy "admin write" on announcements for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "unit read" on calendar_events for select using (unit_id = my_unit_id());
create policy "admin write" on calendar_events for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "unit read" on attendance_sessions for select using (unit_id = my_unit_id());
create policy "admin write" on attendance_sessions for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "own or admin read" on attendance_records for select
  using (cadet_id = auth.uid() or (is_unit_admin() and session_id in
    (select id from attendance_sessions where unit_id = my_unit_id())));
create policy "admin write" on attendance_records for all
  using (is_unit_admin() and session_id in
    (select id from attendance_sessions where unit_id = my_unit_id()))
  with check (is_unit_admin() and session_id in
    (select id from attendance_sessions where unit_id = my_unit_id()));

create policy "own or admin read" on camp_records for select
  using (cadet_id = auth.uid() or (is_unit_admin() and cadet_id in
    (select id from profiles where unit_id = my_unit_id())));
create policy "admin write" on camp_records for all
  using (is_unit_admin() and cadet_id in (select id from profiles where unit_id = my_unit_id()))
  with check (is_unit_admin() and cadet_id in (select id from profiles where unit_id = my_unit_id()));

create policy "shared or unit read" on documents for select
  using (unit_id is null or unit_id = my_unit_id());
create policy "admin write" on documents for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "read chunks of visible docs" on document_chunks for select
  using (document_id in (select id from documents));

create policy "read approved or admin" on questions for select
  using ((unit_id is null or unit_id = my_unit_id())
         and (status = 'approved' or is_unit_admin()));
create policy "admin write" on questions for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "unit read" on tests for select using (unit_id = my_unit_id());
create policy "admin write" on tests for all
  using (is_unit_admin() and unit_id = my_unit_id())
  with check (is_unit_admin() and unit_id = my_unit_id());

create policy "read via test" on test_questions for select
  using (test_id in (select id from tests));
create policy "admin write" on test_questions for all
  using (is_unit_admin() and test_id in (select id from tests where unit_id = my_unit_id()))
  with check (is_unit_admin() and test_id in (select id from tests where unit_id = my_unit_id()));

create policy "own attempts" on test_attempts for all
  using (cadet_id = auth.uid()) with check (cadet_id = auth.uid());
create policy "admin read unit attempts" on test_attempts for select
  using (is_unit_admin() and test_id in (select id from tests where unit_id = my_unit_id()));

create policy "own answers" on attempt_answers for all
  using (attempt_id in (select id from test_attempts where cadet_id = auth.uid()))
  with check (attempt_id in (select id from test_attempts where cadet_id = auth.uid()));
create policy "admin read unit answers" on attempt_answers for select
  using (is_unit_admin() and attempt_id in (select a.id from test_attempts a
    join tests t on t.id = a.test_id where t.unit_id = my_unit_id()));

-- Diary: the cadet owns it. The ANO sees only entries the cadet chose to share.
create policy "own diary" on diary_entries for all
  using (cadet_id = auth.uid()) with check (cadet_id = auth.uid());
create policy "ano reads shared entries" on diary_entries for select
  using (visibility = 'shared_with_unit' and my_role() = 'ano'
         and cadet_id in (select id from profiles where unit_id = my_unit_id()));
