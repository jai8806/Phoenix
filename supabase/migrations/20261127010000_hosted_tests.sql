-- Phoenix: hosted tests (run after the earlier migrations)
-- Admins build a test from approved questions; cadets take it once; the
-- server marks it so scores can't be edited on the phone.

alter table tests add column if not exists description text;
create unique index if not exists test_attempts_once on test_attempts (test_id, cadet_id);

-- Mark and record a cadet's attempt. `answers` maps question id -> chosen
-- option index, e.g. {"<uuid>": 2}. Returns the score.
create or replace function public.submit_attempt(tid uuid, answers jsonb, focus_lost int default 0)
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
  if t.opens_at is not null and now() < t.opens_at then raise exception 'This test has not opened yet'; end if;
  if t.closes_at is not null and now() > t.closes_at + interval '5 minutes' then
    raise exception 'This test has closed';
  end if;
  if exists (select 1 from test_attempts where test_id = tid and cadet_id = auth.uid()) then
    raise exception 'You have already taken this test';
  end if;

  insert into test_attempts (test_id, cadet_id, submitted_at, focus_lost_count)
  values (tid, auth.uid(), now(), coalesce(focus_lost, 0))
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

-- Cadets read their attempts but never write them directly: submit_attempt()
-- is the only way in, so a score can't be edited from the phone.
drop policy if exists "own attempts" on test_attempts;
drop policy if exists "own attempts read" on test_attempts;
create policy "own attempts read" on test_attempts for select using (cadet_id = auth.uid());

drop policy if exists "own answers" on attempt_answers;
drop policy if exists "own answers read" on attempt_answers;
create policy "own answers read" on attempt_answers for select
  using (attempt_id in (select id from test_attempts where cadet_id = auth.uid()));
