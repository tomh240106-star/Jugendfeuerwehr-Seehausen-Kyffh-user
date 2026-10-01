-- Nutzer-Fehlermeldungen für Jugendfeuerwehr Seehausen/Kyffhäuser
-- Ausführen im Supabase SQL Editor, falls Migrationen nicht automatisch deployed werden.

create table if not exists public.user_bug_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text not null check (char_length(description) between 1 and 3000),
  app_area text not null default 'Sonstiges',
  status text not null default 'new' check (status in ('new', 'in_progress', 'done')),
  handled_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_bug_reports enable row level security;

grant select, insert, update on public.user_bug_reports to authenticated;

-- Nutzer dürfen ausschließlich eigene Meldungen erstellen.
drop policy if exists "bug_reports_insert_own" on public.user_bug_reports;
create policy "bug_reports_insert_own"
on public.user_bug_reports for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Nutzer sehen nur eigene Meldungen; Entwickler sehen alle.
drop policy if exists "bug_reports_select_own_or_developer" on public.user_bug_reports;
create policy "bug_reports_select_own_or_developer"
on public.user_bug_reports for select
to authenticated
using (
  (select auth.uid()) = user_id
  or exists (
    select 1 from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

-- Nur freigeschaltete Entwickler dürfen Status/Bearbeiter ändern.
drop policy if exists "bug_reports_update_developer" on public.user_bug_reports;
create policy "bug_reports_update_developer"
on public.user_bug_reports for update
to authenticated
using (
  exists (
    select 1 from public.developer_access da
    where da.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

create index if not exists user_bug_reports_created_at_idx
  on public.user_bug_reports (created_at desc);
create index if not exists user_bug_reports_status_idx
  on public.user_bug_reports (status);
create index if not exists user_bug_reports_user_id_idx
  on public.user_bug_reports (user_id);
