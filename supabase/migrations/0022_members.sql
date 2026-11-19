-- 19 Nov 2026: data member (Daftar Pelanggan Olsera) per bulan di col 'members'. Berisi nomor HP pelanggan,
-- jadi hanya owner, manager, finance yang boleh baca/tulis.
create or replace function public.can_read(c text) returns boolean language sql stable set search_path to 'public' as $$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c in ('daily','sales','olsmonth') then public.my_role() <> 'manager'
    when c in ('requests','sp') then public.my_role() in ('owner','manager','headbar','finance')
    when c in ('hrprofile','perf','members') then public.my_role() in ('owner','manager','finance')
    else true end
$$;
create or replace function public.can_write(c text) returns boolean language sql stable set search_path to 'public' as $$
  select case
    when public.my_role() is null then false
    when c in ('staff','requests') then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c = 'settings' then public.my_role() in ('owner','manager','finance')
    when c in ('daily','sales','olsmonth') and public.my_role() = 'manager' then false
    when c = 'docs' then public.my_role() in ('owner','manager','finance')
    when c = 'recipes' then public.my_role() in ('owner','manager','headbar')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar','finance')
    when c in ('hrprofile','perf','sp','members') then public.my_role() in ('owner','manager','finance')
    when c = 'training' then public.my_role() in ('owner','manager')
    when c = 'logbook' then public.my_role() in ('owner','manager','headbar','finance')
    when c = 'resv' then public.my_role() in ('owner','manager','headbar','finance')
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','stock','closings','voucher')
    else true end
$$;
