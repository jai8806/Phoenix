-- Phoenix: OMR mock exams (run after the earlier migrations)
-- A mock runs like the real paper: the ANO starts it, cadets read the
-- questions on their phones and mark a printed OMR sheet, then photograph
-- the sheet. The phone reads the bubbles; the server marks the answers.

alter table tests add column if not exists mode text not null default 'app';
alter table tests drop constraint if exists tests_mode_check;
alter table tests add constraint tests_mode_check check (mode in ('app', 'omr'));
alter table tests add column if not exists pattern text;          -- 'bcert' | 'ccert'
alter table tests add column if not exists sheet_code int;        -- printed on the sheet
alter table tests add column if not exists started_at timestamptz; -- when the ANO started it
alter table tests add column if not exists upload_minutes int not null default 20;
alter table tests add column if not exists set_seed int;          -- Set A2 question order
create unique index if not exists tests_sheet_code on tests (unit_id, sheet_code) where sheet_code is not null;

alter table test_attempts add column if not exists sheet_path text;  -- photo in the omr-sheets bucket
alter table test_attempts add column if not exists set_label text;   -- 'A1' | 'A2'
alter table test_attempts add column if not exists scan_flags int not null default 0;
alter table test_attempts add column if not exists corrected int not null default 0; -- answers the cadet confirmed by hand

-- Marks and records an attempt; for an OMR mock also the sheet photo and how
-- it was read. answers maps question id -> option (0-3), or -1 for a
-- question marked more than once (counted wrong, as in the real exam).
drop function if exists public.submit_attempt(uuid, jsonb, int);
create or replace function public.submit_attempt(
  tid uuid,
  answers jsonb,
  focus_lost int default 0,
  sheet_path text default null,
  set_label text default null,
  scan_flags int default 0,
  corrected int default 0
)
returns numeric
language plpgsql security definer set search_path = public as $$
declare
  t tests%rowtype;
  attempt uuid;
  total numeric := 0;
  q record;
  chosen int;
begin
  select * into t from tests where id = tid and unit_id = my_unit_id();
  if not found then raise exception 'Test not found'; end if;
  if t.mode = 'omr' and t.started_at is null then raise exception 'This exam has not started yet'; end if;
  if t.opens_at is not null and now() < t.opens_at then raise exception 'This test has not opened yet'; end if;
  if t.closes_at is not null and now() > t.closes_at + interval '5 minutes' then
    raise exception 'This test has closed';
  end if;
  if exists (select 1 from test_attempts where test_id = tid and cadet_id = auth.uid()) then
    raise exception 'You have already taken this test';
  end if;
  if sheet_path is not null and sheet_path not like my_unit_id()::text || '/' || tid::text || '/' || auth.uid()::text || '%' then
    raise exception 'That sheet photo is not yours';
  end if;

  insert into test_attempts (test_id, cadet_id, submitted_at, focus_lost_count, sheet_path, set_label, scan_flags, corrected)
  values (tid, auth.uid(), now(), coalesce(focus_lost, 0), sheet_path, set_label, coalesce(scan_flags, 0), coalesce(corrected, 0))
  returning id into attempt;

  for q in select qu.id, qu.correct_index from test_questions tq join questions qu on qu.id = tq.question_id
           where tq.test_id = tid loop
    chosen := (answers ->> q.id::text)::int;
    insert into attempt_answers (attempt_id, question_id, chosen_index) values (attempt, q.id, chosen);
    if chosen is not null then
      total := total + case when chosen = q.correct_index then t.marks_correct else -t.marks_wrong end;
    end if;
  end loop;

  update test_attempts set score = total where id = attempt;
  return total;
end $$;

-- Sheet photos: <unit>/<test>/<cadet>.jpg. Cadets add and read their own;
-- the unit's ANO and senior cadets read all of their unit's.
insert into storage.buckets (id, name, public)
values ('omr-sheets', 'omr-sheets', false)
on conflict (id) do nothing;

drop policy if exists "cadets upload their own sheet" on storage.objects;
create policy "cadets upload their own sheet" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'omr-sheets'
    and name like public.my_unit_id()::text || '/%/' || auth.uid()::text || '.jpg'
  );

drop policy if exists "cadets replace their own sheet" on storage.objects;
create policy "cadets replace their own sheet" on storage.objects for update to authenticated
  using (bucket_id = 'omr-sheets' and name like public.my_unit_id()::text || '/%/' || auth.uid()::text || '.jpg');

drop policy if exists "own sheet or unit admins read sheets" on storage.objects;
create policy "own sheet or unit admins read sheets" on storage.objects for select to authenticated
  using (
    bucket_id = 'omr-sheets'
    and (
      name like public.my_unit_id()::text || '/%/' || auth.uid()::text || '.jpg'
      or (public.is_unit_admin() and name like public.my_unit_id()::text || '/%')
    )
  );
