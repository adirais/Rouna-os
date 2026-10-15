create table public.docs (
  col text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (col, id)
);
create index docs_col_idx on public.docs (col);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  staff_id text not null unique,
  username text not null unique,
  created_at timestamptz not null default now()
);

alter table public.docs enable row level security;
alter table public.profiles enable row level security;

-- role of the signed-in user, read from their staff doc (null if inactive / unknown)
create or replace function public.my_staff_id() returns text
language sql stable security definer set search_path = public as $$
  select staff_id from public.profiles where user_id = auth.uid()
$$;

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select d.data->>'role' from public.profiles p
  join public.docs d on d.col = 'staff' and d.id = p.staff_id
  where p.user_id = auth.uid() and coalesce((d.data->>'active')::boolean, true)
$$;

create or replace function public.can_read(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs') then public.my_role() in ('owner','manager','finance')
    else true end
$$;

create or replace function public.can_write(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','settings') then public.my_role() in ('owner','manager','finance')
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    else true end
$$;

create policy docs_select on public.docs for select to authenticated using (public.can_read(col));
create policy docs_insert on public.docs for insert to authenticated with check (public.can_write(col));
create policy docs_update on public.docs for update to authenticated using (public.can_write(col)) with check (public.can_write(col));
create policy docs_delete on public.docs for delete to authenticated using (public.can_write(col));

create policy profiles_select on public.profiles for select to authenticated using (public.my_role() is not null);

create or replace function public.jsonb_deep_merge(a jsonb, b jsonb) returns jsonb
language sql immutable set search_path = public as $$
  select case
    when jsonb_typeof(a) = 'object' and jsonb_typeof(b) = 'object' then (
      select coalesce(jsonb_object_agg(k,
        case when a ? k and b ? k then public.jsonb_deep_merge(a->k, b->k)
             when b ? k then b->k else a->k end), '{}'::jsonb)
      from (select jsonb_object_keys(a) k union select jsonb_object_keys(b)) keys)
    else b end
$$;

create or replace function public.docs_touch() returns trigger
language plpgsql set search_path = public as $$
begin new.updated_at := now(); new.updated_by := auth.uid(); return new; end $$;
create trigger docs_touch before insert or update on public.docs for each row execute function public.docs_touch();

-- upsert + deep merge (runs with caller rights, so RLS applies)
create or replace function public.merge_doc(p_col text, p_id text, p_patch jsonb, p_base jsonb default '{}'::jsonb)
returns void language sql security invoker set search_path = public as $$
  insert into public.docs (col, id, data) values (p_col, p_id, public.jsonb_deep_merge(coalesce(p_base,'{}'::jsonb), p_patch))
  on conflict (col, id) do update set data = public.jsonb_deep_merge(public.docs.data, p_patch)
$$;

-- any active staff can mark an SOP document as read (only their own key)
create or replace function public.ack_doc(p_id text) returns void
language plpgsql security definer set search_path = public as $$
declare sid text := public.my_staff_id();
begin
  if public.my_role() is null then raise exception 'not allowed'; end if;
  update public.docs set data = jsonb_set(data, '{ack}', coalesce(data->'ack','{}'::jsonb) || jsonb_build_object(sid, (extract(epoch from now())*1000)::bigint))
  where col = 'docs' and id = p_id;
end $$;

revoke execute on function public.ack_doc(text) from anon, public;
grant execute on function public.ack_doc(text) to authenticated;
revoke execute on function public.my_role() from anon, public;
grant execute on function public.my_role() to authenticated;
revoke execute on function public.my_staff_id() from anon, public;
grant execute on function public.my_staff_id() to authenticated;

-- is there any account yet? (lets the login screen show first-time setup)
create or replace function public.has_accounts() returns boolean
language sql stable security definer set search_path = public as $$ select exists (select 1 from public.profiles) $$;
grant execute on function public.has_accounts() to anon, authenticated;

alter publication supabase_realtime add table public.docs;

-- photos bucket (public read by unguessable name, upload by signed-in staff)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 3145728, array['image/jpeg','image/png','image/webp']) on conflict do nothing;
create policy photos_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and public.my_role() is not null);
