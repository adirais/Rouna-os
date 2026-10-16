-- Crew hanya bisa mencatat absensi, checklist SOP, kalibrasi, waste, dan voucher; hapus data hanya Owner/Manager/Finance
create or replace function public.can_write(c text) returns boolean
language sql stable set search_path = public as $$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','settings','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','manager','finance')
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','voucher')
    else true end
$$;

create or replace function public.can_delete(c text) returns boolean
language sql stable set search_path = public as $$
  select public.can_write(c) and public.my_role() in ('owner','manager','finance')
$$;

alter policy docs_delete on public.docs using (public.can_delete(col));
