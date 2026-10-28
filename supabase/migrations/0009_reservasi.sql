-- 22 Okt 2026: Reservasi meja & acara (koleksi resv/{tanggal}); denah di settings/floor.
-- Reservasi dicatat Owner, Manager, Headbar, Finance; semua staf bisa membaca.
create or replace function public.can_write(c text)
 returns boolean language sql stable set search_path to 'public'
as $function$
  select case
    when public.my_role() is null then false
    when c in ('staff','requests') then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c = 'settings' then public.my_role() in ('owner','manager','finance')
    when c in ('daily','sales','olsmonth') and public.my_role() = 'manager' then false
    when c = 'docs' then public.my_role() in ('owner','manager','finance')
    when c = 'recipes' then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar','finance')
    when c in ('hrprofile','perf') then public.my_role() in ('owner','manager','finance')
    when c = 'training' then public.my_role() in ('owner','manager')
    when c = 'logbook' then public.my_role() in ('owner','manager','headbar','finance')
    when c = 'resv' then public.my_role() in ('owner','manager','headbar','finance')
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','stock','closings','voucher')
    else true end
$function$;
