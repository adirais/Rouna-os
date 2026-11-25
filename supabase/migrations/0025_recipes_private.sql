-- 25 Nov 2026: resep menu tidak boleh dibaca crew/gudang. Hanya owner, manager, finance, headbar, kitchen.
create or replace function public.can_read(c text) returns boolean language sql stable set search_path to 'public' as $$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c in ('daily','sales','olsmonth') then public.my_role() <> 'manager'
    when c in ('requests','sp') then public.my_role() in ('owner','manager','headbar','finance')
    when c in ('hrprofile','perf','members','mktcamp','mktev') then public.my_role() in ('owner','manager','finance')
    when c = 'recipes' then public.my_role() in ('owner','manager','finance','headbar','kitchen')
    else true end
$$;
