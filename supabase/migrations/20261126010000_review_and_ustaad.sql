-- Phoenix: question review and Ustaad support (run after 20261126000000_init.sql)

-- A unit adopts a shared précis question by approving it with an answer. The
-- shared draft stays untouched for other units; the unit gets its own copy.
alter table questions add column if not exists adopted_from uuid references questions (id) on delete set null;
create unique index if not exists questions_unit_adopted_once on questions (unit_id, adopted_from)
  where adopted_from is not null;

-- Approve a shared draft for the caller's unit (ANO or senior cadet only).
create or replace function public.adopt_question(qid uuid, answer smallint, note text default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  src questions%rowtype;
  new_id uuid;
begin
  if not is_unit_admin() then
    raise exception 'Only the ANO or a senior cadet can approve questions';
  end if;
  select * into src from questions where id = qid and unit_id is null;
  if not found then raise exception 'Question not found'; end if;
  if answer < 0 or answer >= array_length(src.options, 1) then
    raise exception 'Answer must be one of the options';
  end if;
  insert into questions (unit_id, subject, wing, prompt, options, correct_index, explanation, status,
                         source_page, adopted_from, created_by)
  values (my_unit_id(), src.subject, src.wing, src.prompt, src.options, answer,
          coalesce(nullif(trim(note), ''), src.explanation), 'approved', src.source_page, src.id, auth.uid())
  on conflict (unit_id, adopted_from) where adopted_from is not null
    do update set correct_index = excluded.correct_index, explanation = excluded.explanation
  returning id into new_id;
  return new_id;
end $$;

-- Shared drafts the caller's unit has not approved yet. Runs with the caller's
-- rights, so only unit admins see anything (drafts are admin-only under RLS).
create or replace function public.review_queue(max_rows int default 50)
returns setof questions
language sql stable set search_path = public as $$
  select q.* from questions q
  where q.unit_id is null and q.status = 'draft'
    and not exists (select 1 from questions a where a.unit_id = my_unit_id() and a.adopted_from = q.id)
  order by q.subject, q.explanation, q.created_at
  limit least(max_rows, 200)
$$;

-- Ustaad usage log: lets the ANO see what cadets ask and keeps a per-user
-- daily cap enforceable. Cadets read only their own rows.
create table if not exists ustaad_log (
  id bigserial primary key,
  user_id uuid not null references profiles (id) on delete cascade,
  question text not null,
  answered boolean not null,
  created_at timestamptz not null default now()
);
alter table ustaad_log enable row level security;
create policy "own log" on ustaad_log for select using (user_id = auth.uid());
create policy "write own log" on ustaad_log for insert with check (user_id = auth.uid());
create policy "ano reads unit log" on ustaad_log for select
  using (my_role() = 'ano' and user_id in (select id from profiles where unit_id = my_unit_id()));
create index if not exists ustaad_log_user_day on ustaad_log (user_id, created_at desc);
