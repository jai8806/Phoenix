-- Phoenix: précis figures (run after the earlier migrations)
-- Figure files live in a private Storage bucket; this table says which
-- chapter and page each one belongs to. Like the précis text, only signed-in
-- members of a unit can read them.

create table if not exists figures (
  id text primary key,
  document_title text not null,
  chapter_code text not null,        -- e.g. "MR-1"
  page smallint,                     -- printed page in the précis
  storage_path text not null unique, -- path inside the precis-figures bucket
  width int,
  height int,
  created_at timestamptz not null default now()
);
create index if not exists figures_chapter_page on figures (chapter_code, page);

alter table figures enable row level security;
drop policy if exists "unit members read figures" on figures;
create policy "unit members read figures" on figures for select using (my_unit_id() is not null);

insert into storage.buckets (id, name, public)
values ('precis-figures', 'precis-figures', false)
on conflict (id) do nothing;

drop policy if exists "unit members read figure files" on storage.objects;
create policy "unit members read figure files" on storage.objects for select to authenticated
  using (bucket_id = 'precis-figures' and public.my_unit_id() is not null);
