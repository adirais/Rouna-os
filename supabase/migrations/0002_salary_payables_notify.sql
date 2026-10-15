-- v2: gaji per orang (salary), utang supplier (payables), jadwal shift (shift), notifikasi Telegram
create or replace function public.can_read(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables') then public.my_role() in ('owner','manager','finance')
    else true end
$$;

create or replace function public.can_write(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','settings','salary','payables') then public.my_role() in ('owner','manager','finance')
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    else true end
$$;

-- server-only secrets (Telegram bot token, chat ids, cron key). No policies = no client access.
create table if not exists public.secrets (key text primary key, value jsonb not null, updated_at timestamptz default now());
alter table public.secrets enable row level security;

create extension if not exists pg_cron;
create extension if not exists pg_net;
insert into public.secrets(key, value) values ('cron_key', to_jsonb(encode(gen_random_bytes(24), 'hex'))) on conflict (key) do nothing;

create or replace function public.rouna_notify(kind text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform net.http_post(
    url := 'https://uknxzineemkqfvseoxte.supabase.co/functions/v1/notify',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('action','cron','kind',kind,'key',(select value #>> '{}' from public.secrets where key='cron_key')));
end $$;
revoke execute on function public.rouna_notify(text) from public, anon, authenticated;

-- times in UTC: 07:45, 14:00, 23:15 WITA
select cron.schedule('rouna-morning', '45 23 * * *', $$select public.rouna_notify('morning')$$);
select cron.schedule('rouna-midday', '0 6 * * *', $$select public.rouna_notify('midday')$$);
select cron.schedule('rouna-closing', '15 15 * * *', $$select public.rouna_notify('closing')$$);
