create extension if not exists "pgcrypto";

do $$ begin
  create type public.user_role as enum ('ausbilder', 'jugendmitglied', 'eltern');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.event_type as enum ('dienst', 'veranstaltung', 'wettbewerb', 'zeltlager', 'elternabend', 'sonstiges');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.attendance_status as enum ('offen', 'zugesagt', 'abgesagt', 'entschuldigt');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.message_scope as enum ('einzelperson', 'gruppe', 'alle');
exception
  when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  role public.user_role not null default 'jugendmitglied',
  phone text,
  avatar_url text,
  notifications_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parent_child (
  parent_id uuid not null references public.profiles(id) on delete cascade,
  child_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (parent_id, child_id)
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  event_type public.event_type not null default 'dienst',
  starts_at timestamptz not null,
  ends_at timestamptz,
  location text,
  meeting_point text,
  required_equipment text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.event_attendance (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.attendance_status not null default 'offen',
  note text,
  updated_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.training_plans (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  valid_from date,
  valid_until date,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.training_units (
  id uuid primary key default gen_random_uuid(),
  training_plan_id uuid not null references public.training_plans(id) on delete cascade,
  event_id uuid references public.events(id) on delete set null,
  title text not null,
  topic text,
  objectives text,
  duration_minutes integer,
  equipment text,
  content text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  title text,
  scope public.message_scope not null default 'einzelperson',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios', 'web')),
  created_at timestamptz not null default now()
);

create or replace function public.current_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

alter table public.profiles enable row level security;
alter table public.parent_child enable row level security;
alter table public.events enable row level security;
alter table public.event_attendance enable row level security;
alter table public.training_plans enable row level security;
alter table public.training_units enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;
alter table public.device_tokens enable row level security;

drop policy if exists "profile_self_select" on public.profiles;
create policy "profile_self_select" on public.profiles for select using (id = auth.uid());

drop policy if exists "trainer_profiles_select" on public.profiles;
create policy "trainer_profiles_select" on public.profiles for select using (public.current_role() = 'ausbilder');

drop policy if exists "profile_self_update" on public.profiles;
create policy "profile_self_update" on public.profiles for update using (id = auth.uid());

drop policy if exists "profile_self_insert" on public.profiles;
create policy "profile_self_insert" on public.profiles for insert with check (id = auth.uid());

drop policy if exists "events_authenticated_read" on public.events;
create policy "events_authenticated_read" on public.events for select to authenticated using (true);

drop policy if exists "events_trainer_insert" on public.events;
create policy "events_trainer_insert" on public.events for insert with check (
  public.current_role() = 'ausbilder' and created_by = auth.uid()
);

drop policy if exists "events_trainer_update" on public.events;
create policy "events_trainer_update" on public.events for update using (public.current_role() = 'ausbilder');

drop policy if exists "events_trainer_delete" on public.events;
create policy "events_trainer_delete" on public.events for delete using (public.current_role() = 'ausbilder');

drop policy if exists "attendance_self_or_trainer_select" on public.event_attendance;
create policy "attendance_self_or_trainer_select" on public.event_attendance for select using (
  user_id = auth.uid() or public.current_role() = 'ausbilder'
);

drop policy if exists "attendance_self_insert" on public.event_attendance;
create policy "attendance_self_insert" on public.event_attendance for insert with check (user_id = auth.uid());

drop policy if exists "attendance_self_update" on public.event_attendance;
create policy "attendance_self_update" on public.event_attendance for update using (
  user_id = auth.uid() or public.current_role() = 'ausbilder'
);

drop policy if exists "training_plan_read" on public.training_plans;
create policy "training_plan_read" on public.training_plans for select to authenticated using (true);

drop policy if exists "training_plan_trainer_manage" on public.training_plans;
create policy "training_plan_trainer_manage" on public.training_plans for all using (public.current_role() = 'ausbilder')
with check (public.current_role() = 'ausbilder');

drop policy if exists "training_unit_read" on public.training_units;
create policy "training_unit_read" on public.training_units for select to authenticated using (true);

drop policy if exists "training_unit_trainer_manage" on public.training_units;
create policy "training_unit_trainer_manage" on public.training_units for all using (public.current_role() = 'ausbilder')
with check (public.current_role() = 'ausbilder');

drop policy if exists "parent_child_select" on public.parent_child;
create policy "parent_child_select" on public.parent_child for select using (
  parent_id = auth.uid() or child_id = auth.uid() or public.current_role() = 'ausbilder'
);

drop policy if exists "parent_child_trainer_manage" on public.parent_child;
create policy "parent_child_trainer_manage" on public.parent_child for all using (public.current_role() = 'ausbilder')
with check (public.current_role() = 'ausbilder');

drop policy if exists "notifications_self_read" on public.notifications;
create policy "notifications_self_read" on public.notifications for select using (user_id = auth.uid());

drop policy if exists "device_tokens_self" on public.device_tokens;
create policy "device_tokens_self" on public.device_tokens for all using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "conversation_member_read" on public.conversations;
create policy "conversation_member_read" on public.conversations for select using (
  exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = id and cm.user_id = auth.uid()
  )
  or public.current_role() = 'ausbilder'
);

drop policy if exists "conversation_create" on public.conversations;
create policy "conversation_create" on public.conversations for insert with check (created_by = auth.uid());

drop policy if exists "conversation_members_read" on public.conversation_members;
create policy "conversation_members_read" on public.conversation_members for select using (
  user_id = auth.uid() or public.current_role() = 'ausbilder'
);

drop policy if exists "conversation_members_manage" on public.conversation_members;
create policy "conversation_members_manage" on public.conversation_members for insert with check (
  public.current_role() = 'ausbilder' or user_id = auth.uid()
);

drop policy if exists "messages_member_read" on public.messages;
create policy "messages_member_read" on public.messages for select using (
  exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()
  )
);

drop policy if exists "messages_member_send" on public.messages;
create policy "messages_member_send" on public.messages for insert with check (
  sender_id = auth.uid()
  and exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = messages.conversation_id and cm.user_id = auth.uid()
  )
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, first_name, last_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    coalesce((new.raw_user_meta_data->>'role')::public.user_role, 'jugendmitglied')
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();


drop policy if exists "trainer_profile_update" on public.profiles;
create policy "trainer_profile_update" on public.profiles
for update using (public.current_role() = 'ausbilder');

drop policy if exists "attendance_trainer_insert" on public.event_attendance;
create policy "attendance_trainer_insert" on public.event_attendance
for insert with check (public.current_role() = 'ausbilder');

drop policy if exists "conversation_members_trainer_select" on public.conversation_members;
create policy "conversation_members_trainer_select" on public.conversation_members
for select using (
  user_id = auth.uid() or public.current_role() = 'ausbilder'
);


create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text not null default 'Allgemein',
  file_name text not null,
  storage_path text not null unique,
  mime_type text,
  uploaded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

alter table public.documents enable row level security;

drop policy if exists "documents_authenticated_read" on public.documents;
create policy "documents_authenticated_read" on public.documents
for select to authenticated using (true);

drop policy if exists "documents_trainer_insert" on public.documents;
create policy "documents_trainer_insert" on public.documents
for insert with check (
  public.current_role() = 'ausbilder' and uploaded_by = auth.uid()
);

drop policy if exists "documents_trainer_delete" on public.documents;
create policy "documents_trainer_delete" on public.documents
for delete using (public.current_role() = 'ausbilder');

insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists "documents_storage_read" on storage.objects;
create policy "documents_storage_read" on storage.objects
for select to authenticated using (bucket_id = 'documents');

drop policy if exists "documents_storage_trainer_insert" on storage.objects;
create policy "documents_storage_trainer_insert" on storage.objects
for insert to authenticated with check (
  bucket_id = 'documents'
  and public.current_role() = 'ausbilder'
);

drop policy if exists "documents_storage_trainer_delete" on storage.objects;
create policy "documents_storage_trainer_delete" on storage.objects
for delete to authenticated using (
  bucket_id = 'documents'
  and public.current_role() = 'ausbilder'
);
