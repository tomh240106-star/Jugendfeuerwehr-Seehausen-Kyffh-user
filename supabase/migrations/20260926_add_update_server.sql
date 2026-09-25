-- Jugendfeuerwehr Seehausen/Kyffhäuser

-- Privater APK-Bucket für App-Updates
insert into storage.buckets (id, name, public)
values ('app-updates', 'app-updates', false)
on conflict (id) do update
set public = false;

-- Update-Server: NON / BETA / FOR ALL
--
-- Voraussetzung:
-- Die bestehende Tabelle public.developer_access bleibt die alleinige
-- Quelle für Entwicklerrechte.
--
-- WICHTIG:
-- Lege in Supabase Storage einmalig einen PRIVATEN Bucket mit dem Namen
-- "app-updates" an. Der Bucket darf NICHT public sein.
--
-- Danach dieses SQL im Supabase SQL-Editor ausführen.

create table if not exists public.app_beta_users (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'android'
    check (platform in ('android')),
  version_name text not null,
  build_number integer not null
    check (build_number > 0),
  channel text not null default 'non'
    check (channel in ('non', 'beta', 'forall')),
  storage_path text not null unique,
  sha256 text not null
    check (sha256 ~ '^[0-9a-fA-F]{64}$'),
  file_size_bytes bigint,
  notes text,
  force_update boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (platform, build_number)
);

create index if not exists app_releases_channel_build_idx
  on public.app_releases(platform, channel, is_active, build_number desc);

create index if not exists app_releases_created_by_idx
  on public.app_releases(created_by);

create index if not exists app_releases_updated_by_idx
  on public.app_releases(updated_by);

create index if not exists app_beta_users_enabled_idx
  on public.app_beta_users(user_id)
  where enabled = true;

create index if not exists app_beta_users_granted_by_idx
  on public.app_beta_users(granted_by);

alter table public.app_beta_users enable row level security;
alter table public.app_releases enable row level security;

revoke all on table public.app_beta_users from anon, authenticated;
revoke all on table public.app_releases from anon, authenticated;

grant select, insert, update, delete
  on table public.app_beta_users to authenticated;

grant select, insert, update, delete
  on table public.app_releases to authenticated;

grant all on table public.app_beta_users to service_role;
grant all on table public.app_releases to service_role;

-- Beta-Nutzer dürfen ausschließlich ihren eigenen Beta-Status lesen.
-- Entwickler dürfen die komplette Liste lesen.
drop policy if exists app_beta_users_select on public.app_beta_users;
create policy app_beta_users_select
on public.app_beta_users
for select
to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

drop policy if exists app_beta_users_insert_developer on public.app_beta_users;
create policy app_beta_users_insert_developer
on public.app_beta_users
for insert
to authenticated
with check (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
  and granted_by = (select auth.uid())
);

drop policy if exists app_beta_users_update_developer on public.app_beta_users;
create policy app_beta_users_update_developer
on public.app_beta_users
for update
to authenticated
using (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

drop policy if exists app_beta_users_delete_developer on public.app_beta_users;
create policy app_beta_users_delete_developer
on public.app_beta_users
for delete
to authenticated
using (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

-- Releases:
-- NON     -> nur im Entwicklerbereich sichtbar, nie in der normalen Updateprüfung.
-- BETA    -> Entwickler + aktivierte Beta-Nutzer.
-- FOR ALL -> jeder angemeldete App-Nutzer.
drop policy if exists app_releases_select on public.app_releases;
create policy app_releases_select
on public.app_releases
for select
to authenticated
using (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
  or (
    is_active = true
    and (
      channel = 'forall'
      or (
        channel = 'beta'
        and exists (
          select 1
          from public.app_beta_users bu
          where bu.user_id = (select auth.uid())
            and bu.enabled = true
        )
      )
    )
  )
);

drop policy if exists app_releases_insert_developer on public.app_releases;
create policy app_releases_insert_developer
on public.app_releases
for insert
to authenticated
with check (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
  and created_by = (select auth.uid())
  and updated_by = (select auth.uid())
);

drop policy if exists app_releases_update_developer on public.app_releases;
create policy app_releases_update_developer
on public.app_releases
for update
to authenticated
using (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
  and updated_by = (select auth.uid())
);

drop policy if exists app_releases_delete_developer on public.app_releases;
create policy app_releases_delete_developer
on public.app_releases
for delete
to authenticated
using (
  exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

-- Storage-Sicherheit für den privaten Bucket "app-updates".
-- Vorhandene Policies mit diesen Namen werden ersetzt.
drop policy if exists app_updates_select_authorized
  on storage.objects;

create policy app_updates_select_authorized
on storage.objects
for select
to authenticated
using (
  bucket_id = 'app-updates'
  and (
    exists (
      select 1
      from public.developer_access da
      where da.user_id = (select auth.uid())
    )
    or exists (
      select 1
      from public.app_releases r
      where r.storage_path = storage.objects.name
        and r.platform = 'android'
        and r.is_active = true
        and (
          r.channel = 'forall'
          or (
            r.channel = 'beta'
            and exists (
              select 1
              from public.app_beta_users bu
              where bu.user_id = (select auth.uid())
                and bu.enabled = true
            )
          )
        )
    )
  )
);

drop policy if exists app_updates_insert_developer
  on storage.objects;

create policy app_updates_insert_developer
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'app-updates'
  and exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

drop policy if exists app_updates_update_developer
  on storage.objects;

create policy app_updates_update_developer
on storage.objects
for update
to authenticated
using (
  bucket_id = 'app-updates'
  and exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
)
with check (
  bucket_id = 'app-updates'
  and exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);

drop policy if exists app_updates_delete_developer
  on storage.objects;

create policy app_updates_delete_developer
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'app-updates'
  and exists (
    select 1
    from public.developer_access da
    where da.user_id = (select auth.uid())
  )
);
