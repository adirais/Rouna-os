-- Crew boleh ambil barang dari gudang, catat waste, dan closing (masukan tim 16 Okt 2026).
-- Tetap tidak bisa: keuangan, gaji, order, resep, pengaturan, hapus data.
create or replace function public.can_write(c text)
 returns boolean
 language sql
 stable
 set search_path to 'public'
as $function$
  select case
    when public.my_role() is null then false
    when c = 'staff' then false
    when c = 'cash' then public.my_role() in ('owner','manager','finance','headbar')
    when c in ('expenses','payroll','briefs','settings','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','manager','finance')
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    -- crew: absensi, SOP, kalibrasi, mutasi (ambil barang & waste), stok area, closing, voucher
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','stock','closings','voucher')
    else true end
$function$;
