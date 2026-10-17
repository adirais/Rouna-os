-- 17 Okt 2026: Manager tidak bisa mengakses laporan keuangan & penjualan.
-- Keuangan (kas, pengeluaran, gaji, brief, utang, bank, aset): Owner & Finance (kas juga Headbar).
-- Penjualan Olsera (daily, sales, olsmonth): semua kecuali Manager (Crew tetap tidak bisa menulis).
create or replace function public.can_read(c text)
 returns boolean language sql stable set search_path to 'public'
as $function$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c in ('daily','sales','olsmonth') then public.my_role() <> 'manager'
    else true end
$function$;

create or replace function public.can_write(c text)
 returns boolean language sql stable set search_path to 'public'
as $function$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c = 'settings' then public.my_role() in ('owner','manager','finance')
    when c in ('daily','sales','olsmonth') and public.my_role() = 'manager' then false
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    -- crew: absensi, SOP, kalibrasi, mutasi (ambil barang & waste), stok area, closing, voucher
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','stock','closings','voucher')
    else true end
$function$;
