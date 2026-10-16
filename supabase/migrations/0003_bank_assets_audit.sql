-- v3 (ala Accurate): akun kas & bank (bank, banktx), aset tetap (assets), log aktivitas (audit)
create or replace function public.can_read(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','manager','finance')
    else true end
$$;

create or replace function public.can_write(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','settings','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','manager','finance')
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    else true end
$$;

create table if not exists public.audit (
  id bigint generated always as identity primary key,
  ts timestamptz not null default now(),
  user_id uuid, staff_id text, op text not null, col text not null, doc_id text not null, changes jsonb
);
create index if not exists audit_ts_idx on public.audit (ts desc);
alter table public.audit enable row level security;
create policy audit_select on public.audit for select to authenticated using (public.my_role() = 'owner');

create or replace function public.docs_audit() returns trigger
language plpgsql security definer set search_path = public as $$
declare ch jsonb := '[]'::jsonb; k text; sub jsonb;
begin
  if coalesce(new.col, old.col) = 'stock' then return null; end if;
  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(new.data) union select jsonb_object_keys(old.data) loop
      if (old.data->k) is distinct from (new.data->k) then
        if jsonb_typeof(new.data->k) = 'object' and jsonb_typeof(old.data->k) = 'object' then
          select coalesce(jsonb_agg(s), '[]'::jsonb) into sub from (
            select s from (select jsonb_object_keys(new.data->k) s union select jsonb_object_keys(old.data->k)) x
            where (old.data->k->s) is distinct from (new.data->k->s) limit 6) y;
          ch := ch || jsonb_build_object('k', k, 'sub', sub);
        else
          ch := ch || jsonb_build_object('k', k);
        end if;
      end if;
    end loop;
    if ch = '[]'::jsonb then return null; end if;
  end if;
  insert into public.audit(user_id, staff_id, op, col, doc_id, changes)
  values (auth.uid(), (select staff_id from public.profiles where user_id = auth.uid()), tg_op, coalesce(new.col, old.col), coalesce(new.id, old.id), ch);
  return null;
end $$;
create trigger docs_audit after insert or update or delete on public.docs for each row execute function public.docs_audit();

select cron.schedule('rouna-audit-retention', '0 19 * * *', $$delete from public.audit where ts < now() - interval '120 days'$$);
