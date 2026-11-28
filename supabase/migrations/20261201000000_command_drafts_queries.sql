-- Phoenix: unit command structure, mock drafts and anonymous queries
-- (run after the earlier migrations)
--
-- 1. Appointments. ANO, CSUO and SUO command the unit (roster, publishing
--    mocks); JUO, CSM and CQMS assist (Command Center, but no roster).
-- 2. Mock drafts. A generated mock stays a draft, visible only to admins,
--    until a CSUO / SUO / ANO checks it and publishes it.
-- 3. Anonymous queries. A cadet asks a question without their name being
--    stored anywhere. Only the CSUO / SUO (and, if the cadet chooses, JUO,
--    CSM and CQMS) can read it; the ANO cannot. Seniors take serious issues
--    to the ANO in person.

-- ---------------------------------------------------------------------------
-- 1. Appointments
-- ---------------------------------------------------------------------------
alter table profiles add column if not exists appointment text;
alter table profiles drop constraint if exists profiles_appointment_check;
alter table profiles add constraint profiles_appointment_check
  check (appointment is null or (appointment in ('csuo', 'suo', 'juo', 'csm', 'cqms') and role = 'senior_cadet'));

create or replace function public.my_appointment() returns text
language sql stable security definer set search_path = public as $$
  select appointment from profiles where id = auth.uid()
$$;

-- ANO, CSUO and SUO.
create or replace function public.is_unit_command() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_role() = 'ano' or (my_role() = 'senior_cadet' and my_appointment() in ('csuo', 'suo')), false)
$$;

-- Nobody changes their own role or appointment.
drop policy if exists "edit self" on profiles;
create policy "edit self" on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and role = my_role()
              and appointment is not distinct from my_appointment()
              and unit_id is not distinct from my_unit_id());

-- The ANO, CSUO and SUO manage the roster. Only the ANO can touch the
-- ANO's profile or make someone ANO.
drop policy if exists "ano manages unit profiles" on profiles;
drop policy if exists "command manages unit profiles" on profiles;
create policy "command manages unit profiles" on profiles for update
  using (is_unit_command() and unit_id = my_unit_id() and id <> auth.uid() and (my_role() = 'ano' or role <> 'ano'))
  with check (is_unit_command() and id <> auth.uid() and (unit_id = my_unit_id() or unit_id is null) and (my_role() = 'ano' or role <> 'ano'));

-- ---------------------------------------------------------------------------
-- 2. Mock drafts
-- ---------------------------------------------------------------------------
alter table tests add column if not exists is_draft boolean not null default false;
alter table tests add column if not exists published_by uuid references profiles (id) on delete set null;

drop policy if exists "unit read" on tests;
create policy "unit read" on tests for select
  using (unit_id = my_unit_id() and (not is_draft or is_unit_admin()));

-- Only the ANO, CSUO or SUO publish a draft.
create or replace function public.guard_test_publish() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.is_draft and not new.is_draft then
    if not is_unit_command() then
      raise exception 'Only the ANO, CSUO or SUO can publish a mock';
    end if;
    new.published_by := auth.uid();
  end if;
  if not old.is_draft and new.is_draft then
    raise exception 'A published test cannot go back to draft';
  end if;
  return new;
end $$;
drop trigger if exists tests_guard_publish on tests;
create trigger tests_guard_publish before update on tests
  for each row execute function public.guard_test_publish();

-- Nobody sits a draft.
create or replace function public.block_draft_attempts() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from tests where id = new.test_id and is_draft) then
    raise exception 'This test has not been published yet';
  end if;
  return new;
end $$;
drop trigger if exists test_attempts_not_draft on test_attempts;
create trigger test_attempts_not_draft before insert on test_attempts
  for each row execute function public.block_draft_attempts();

-- Replaces a test's questions in one go (editing a draft).
create or replace function public.set_test_questions(tid uuid, qids uuid[], positions int[])
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_unit_admin() then raise exception 'Only admins can edit tests'; end if;
  if not exists (select 1 from tests where id = tid and unit_id = my_unit_id()) then
    raise exception 'Test not found';
  end if;
  if exists (select 1 from test_attempts where test_id = tid) then
    raise exception 'Cadets have already taken this test; its questions can no longer change';
  end if;
  if coalesce(array_length(qids, 1), 0) <> coalesce(array_length(positions, 1), 0) then
    raise exception 'Each question needs a number';
  end if;
  if exists (select 1 from unnest(qids) q left join questions qu on qu.id = q
             where qu.id is null or not (qu.unit_id is null or qu.unit_id = my_unit_id())) then
    raise exception 'Unknown question';
  end if;
  delete from test_questions where test_id = tid;
  insert into test_questions (test_id, question_id, position)
    select tid, u.q, u.p from unnest(qids, positions) as u(q, p);
end $$;

-- ---------------------------------------------------------------------------
-- 3. Anonymous queries
-- ---------------------------------------------------------------------------
-- No column here identifies the asker. The asker's phone keeps a random
-- ticket code; only its SHA-256 is stored, and replies are fetched with it.
create table if not exists queries (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units (id) on delete cascade,
  token_hash text not null unique,
  category text not null default 'other'
    check (category in ('personal', 'ragging', 'health', 'studies', 'camp', 'unit', 'other')),
  audience text not null default 'command' check (audience in ('command', 'seniors')),
  subject text not null check (char_length(subject) between 3 and 120),
  status text not null default 'open' check (status in ('open', 'answered', 'escalated', 'closed')),
  -- Rounded so the time can't be matched to who was using the app.
  created_at timestamptz not null default date_trunc('hour', now()),
  updated_at timestamptz not null default date_trunc('minute', now())
);
create index if not exists queries_unit on queries (unit_id, updated_at desc);

create table if not exists query_messages (
  id uuid primary key default gen_random_uuid(),
  query_id uuid not null references queries (id) on delete cascade,
  from_senior boolean not null,
  senior_id uuid references profiles (id) on delete set null, -- who answered; null for the asker
  senior_label text,                                         -- e.g. 'CSUO', as shown to the asker
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default date_trunc('minute', now())
);
create index if not exists query_messages_query on query_messages (query_id, created_at);

-- Rate limit only: how many queries someone sent today, never which ones.
create table if not exists query_quota (
  user_id uuid not null references profiles (id) on delete cascade,
  day date not null,
  n int not null default 0,
  primary key (user_id, day)
);

alter table queries enable row level security;
alter table query_messages enable row level security;
alter table query_quota enable row level security; -- no policies: only the functions below touch it

create or replace function public.can_handle_query(q_unit uuid, q_audience text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and unit_id = q_unit and role = 'senior_cadet'
      and (appointment in ('csuo', 'suo') or (q_audience = 'seniors' and appointment in ('juo', 'csm', 'cqms')))
  )
$$;

drop function if exists public.my_queries(text[]);
drop policy if exists "handlers read queries" on queries;
create policy "handlers read queries" on queries for select using (can_handle_query(unit_id, audience));
drop policy if exists "handlers read messages" on query_messages;
create policy "handlers read messages" on query_messages for select using (query_id in (select id from queries));
-- (No insert/update/delete policies: everything goes through the functions.)

create or replace function public.query_token_hash(token text) returns text
language sql immutable as $$
  select encode(sha256(convert_to(token, 'UTF8')), 'hex')
$$;

create or replace function public.ask_query(token text, subject text, body text,
                                            category text default 'other', audience text default 'command')
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  unit uuid := my_unit_id();
  sent int;
  qid uuid;
begin
  if unit is null then raise exception 'Join your unit first'; end if;
  if token is null or char_length(token) < 20 then raise exception 'Bad ticket code'; end if;
  if char_length(trim(coalesce(subject, ''))) < 3 then raise exception 'Give your query a short title'; end if;
  if char_length(trim(coalesce(body, ''))) < 5 then raise exception 'Write a little more so the seniors can help'; end if;
  insert into query_quota (user_id, day, n) values (auth.uid(), current_date, 1)
    on conflict (user_id, day) do update set n = query_quota.n + 1
    returning n into sent;
  if sent > 5 then raise exception 'You can send up to 5 queries a day. Add to an existing one instead.'; end if;
  insert into queries (unit_id, token_hash, category, audience, subject)
    values (unit, query_token_hash(token), coalesce(category, 'other'), coalesce(audience, 'command'), trim(subject))
    returning id into qid;
  insert into query_messages (query_id, from_senior, body) values (qid, false, trim(body));
  return qid;
end $$;

-- The asker's own queries, found by their ticket codes (each row says which
-- code it belongs to, so the phone can reply with it).
create or replace function public.my_queries(tokens text[])
returns table (id uuid, token text, subject text, category text, audience text, status text,
               created_at timestamptz, updated_at timestamptz, messages jsonb)
language sql stable security definer set search_path = public as $$
  select q.id, t.token, q.subject, q.category, q.audience, q.status, q.created_at, q.updated_at,
         coalesce((select jsonb_agg(jsonb_build_object(
                     'id', m.id, 'from_senior', m.from_senior, 'senior_label', m.senior_label,
                     'body', m.body, 'created_at', m.created_at) order by m.created_at)
                   from query_messages m where m.query_id = q.id), '[]'::jsonb)
  from unnest(tokens) as t(token)
  join queries q on q.token_hash = query_token_hash(t.token)
  where q.unit_id = my_unit_id()
  order by q.updated_at desc
$$;

-- A reply. With the ticket code it is the asker's; otherwise the caller must
-- be allowed to handle the query, and the reply carries their appointment.
create or replace function public.add_query_message(qid uuid, body text, token text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  q queries%rowtype;
  label text;
begin
  select * into q from queries where id = qid and unit_id = my_unit_id();
  if not found then raise exception 'Query not found'; end if;
  if char_length(trim(coalesce(body, ''))) < 1 then raise exception 'Write a reply'; end if;
  if token is not null then
    if q.token_hash <> query_token_hash(token) then raise exception 'Query not found'; end if;
    if q.status = 'closed' then raise exception 'This query is closed. Ask a new one.'; end if;
    insert into query_messages (query_id, from_senior, body) values (qid, false, trim(body));
    update queries set status = case when status = 'answered' then 'open' else status end,
                       updated_at = date_trunc('minute', now()) where id = qid;
  else
    if not can_handle_query(q.unit_id, q.audience) then raise exception 'Query not found'; end if;
    select upper(appointment) into label from profiles where id = auth.uid();
    insert into query_messages (query_id, from_senior, senior_id, senior_label, body)
      values (qid, true, auth.uid(), label, trim(body));
    update queries set status = case when status = 'open' then 'answered' else status end,
                       updated_at = date_trunc('minute', now()) where id = qid;
  end if;
end $$;

-- Seniors: answered / raised with the ANO / closed. The asker can close theirs.
create or replace function public.set_query_status(qid uuid, new_status text, token text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare q queries%rowtype;
begin
  select * into q from queries where id = qid and unit_id = my_unit_id();
  if not found then raise exception 'Query not found'; end if;
  if new_status not in ('open', 'answered', 'escalated', 'closed') then raise exception 'Unknown status'; end if;
  if token is not null then
    if q.token_hash <> query_token_hash(token) or new_status <> 'closed' then raise exception 'Query not found'; end if;
  elsif not can_handle_query(q.unit_id, q.audience) then
    raise exception 'Query not found';
  end if;
  update queries set status = new_status, updated_at = date_trunc('minute', now()) where id = qid;
end $$;

grant execute on function public.ask_query(text, text, text, text, text) to authenticated;
grant execute on function public.my_queries(text[]) to authenticated;
grant execute on function public.add_query_message(uuid, text, text) to authenticated;
grant execute on function public.set_query_status(uuid, text, text) to authenticated;
grant execute on function public.set_test_questions(uuid, uuid[], int[]) to authenticated;
