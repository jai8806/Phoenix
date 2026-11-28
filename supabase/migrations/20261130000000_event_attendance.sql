-- Phoenix: event roll-call (run after the earlier migrations)
-- The ANO or a senior cadet asks cadets to confirm an event. Each cadet says
-- they're coming, or that they have permission to be absent and why. On the
-- day, admins tick who actually came.

alter table calendar_events add column if not exists details text;           -- the message, as on WhatsApp
alter table calendar_events add column if not exists needs_response boolean not null default false;
alter table calendar_events add column if not exists respond_by timestamptz;  -- null: until the event starts

create table if not exists event_responses (
  event_id uuid not null references calendar_events (id) on delete cascade,
  cadet_id uuid not null references profiles (id) on delete cascade,
  status text not null check (status in ('coming', 'absent')),
  reason text,
  responded_at timestamptz not null default now(),
  attended boolean,                       -- set by admins on the day
  marked_by uuid references profiles (id),
  marked_at timestamptz,
  primary key (event_id, cadet_id),
  check (status = 'coming' or length(trim(coalesce(reason, ''))) >= 3)
);

alter table event_responses enable row level security;

drop policy if exists "own response or unit admins read" on event_responses;
create policy "own response or unit admins read" on event_responses for select
  using (
    cadet_id = auth.uid()
    or (is_unit_admin() and event_id in (select id from calendar_events where unit_id = my_unit_id()))
  );

-- Admins can record or correct anyone's response and mark attendance.
drop policy if exists "unit admins write responses" on event_responses;
create policy "unit admins write responses" on event_responses for all
  using (is_unit_admin() and event_id in (select id from calendar_events where unit_id = my_unit_id()))
  with check (
    is_unit_admin()
    and event_id in (select id from calendar_events where unit_id = my_unit_id())
    and cadet_id in (select id from profiles where unit_id = my_unit_id())
  );

-- A cadet answers for themselves: coming, or absent with a reason. They can
-- change their answer until the reply-by time (or the start of the event).
-- Attendance marks stay with the admins.
create or replace function public.respond_to_event(eid uuid, status text, reason text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  e calendar_events%rowtype;
begin
  select * into e from calendar_events where id = eid and unit_id = my_unit_id();
  if not found then raise exception 'Event not found'; end if;
  if not e.needs_response then raise exception 'This event does not ask for a response'; end if;
  if now() > coalesce(e.respond_by, e.starts_at) then raise exception 'Responses for this event have closed'; end if;
  if status not in ('coming', 'absent') then raise exception 'Choose coming or absent'; end if;
  if status = 'absent' and length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'Give a reason for being absent';
  end if;
  insert into event_responses (event_id, cadet_id, status, reason, responded_at)
  values (eid, auth.uid(), status, case when status = 'absent' then trim(reason) end, now())
  on conflict (event_id, cadet_id) do update
    set status = excluded.status, reason = excluded.reason, responded_at = now();
end $$;
