-- 17 Okt 2026: fitur Tim (HR) — pengajuan cuti/izin/sakit, tukar shift, lembur; profil karyawan;
-- kinerja bulanan; pelatihan (kuis); log shift.
-- Koleksi baru:
--   requests/{id}   pengajuan. Tulis hanya lewat RPC hr_* (bukan tulis langsung).
--                   Baca langsung: penyetuju (owner, manager, headbar, finance). Staf lain lewat hr_mine().
--   hrprofile/{sid} profil karyawan (tgl masuk, kontrak, kontak darurat). Owner/Manager/Finance.
--   perf/{YYYY-MM}  nilai kinerja dari Manager. Owner/Manager/Finance; staf melihat nilainya sendiri lewat hr_mine().
--   training/{sid}  hasil kuis pelatihan. Baca semua; tulis lewat hr_quiz() (Owner/Manager boleh langsung).
--   logbook/{date}  log shift. Baca semua; tulis Owner/Manager/Headbar.

create or replace function public.can_read(c text)
 returns boolean language sql stable set search_path to 'public'
as $function$
  select case
    when public.my_role() is null then false
    when c = 'cash' then public.my_role() in ('owner','finance','headbar')
    when c in ('expenses','payroll','briefs','salary','payables','bank','banktx','assets') then public.my_role() in ('owner','finance')
    when c in ('daily','sales','olsmonth') then public.my_role() <> 'manager'
    when c = 'requests' then public.my_role() in ('owner','manager','headbar','finance')
    when c in ('hrprofile','perf') then public.my_role() in ('owner','manager','finance')
    else true end
$function$;

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
    when c in ('docs','recipes') then public.my_role() in ('owner','manager')
    when c = 'shift' then public.my_role() in ('owner','manager','headbar')
    when c in ('hrprofile','perf') then public.my_role() in ('owner','manager','finance')
    when c = 'training' then public.my_role() in ('owner','manager')
    when c = 'logbook' then public.my_role() in ('owner','manager','headbar')
    -- crew: absensi, SOP, kalibrasi, mutasi (ambil barang & waste), stok area, closing, voucher
    when public.my_role() = 'crew' then c in ('attendance','sop','calib','moves','stock','closings','voucher')
    else true end
$function$;

create or replace function public.hr_is_approver() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('owner','manager','headbar','finance'), false)
$$;

-- jatah cuti tahunan: hrprofile.cutiQuota bila diisi; selain itu 12 hari bila sudah 1 tahun kerja
-- per tanggal p_on (tanggal masuk kosong = dianggap sudah memenuhi).
create or replace function public.hr_quota(p_sid text, p_on date) returns int
language plpgsql stable security definer set search_path = public as $$
declare p jsonb; j date;
begin
  select data into p from docs where col = 'hrprofile' and id = p_sid;
  if p ? 'cutiQuota' and coalesce(p->>'cutiQuota','') <> '' then return (p->>'cutiQuota')::int; end if;
  j := nullif(p->>'join','')::date;
  if j is null or j <= p_on - interval '1 year' then return 12; end if;
  return 0;
end $$;

-- hari cuti terpakai (disetujui + menunggu) pada tahun p_year, kecuali pengajuan p_skip
create or replace function public.hr_cuti_used(p_sid text, p_year int, p_skip text default null) returns int
language sql stable security definer set search_path = public as $$
  select coalesce(sum(((data->>'to')::date - (data->>'from')::date) + 1), 0)::int
  from docs where col = 'requests' and data->>'sid' = p_sid and data->>'type' = 'cuti'
    and data->>'status' in ('menunggu','disetujui') and extract(year from (data->>'from')::date) = p_year
    and (p_skip is null or id <> p_skip)
$$;

create or replace function public.hr_request(p jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare
  me text := public.my_staff_id(); t text := p->>'type'; f date; tt date; d2 date; nid text; q int; used int;
  body jsonb; partner text := nullif(p->>'partner','');
begin
  if public.my_role() is null or me is null then raise exception 'Akun tidak aktif.'; end if;
  if t not in ('cuti','izin','sakit','swap','lembur') then raise exception 'Jenis pengajuan tidak dikenal.'; end if;
  f := (p->>'from')::date; tt := coalesce(nullif(p->>'to','')::date, f);
  if f is null then raise exception 'Tanggal wajib diisi.'; end if;
  if tt < f or tt - f > 30 then raise exception 'Rentang tanggal maksimal 31 hari.'; end if;
  if t in ('swap','lembur') then tt := f; end if;
  if t = 'cuti' then
    q := public.hr_quota(me, f); used := public.hr_cuti_used(me, extract(year from f)::int);
    if used + (tt - f + 1) > q then raise exception 'Sisa cuti tidak cukup: sisa % hari, diajukan % hari.', greatest(q - used, 0), tt - f + 1; end if;
  end if;
  if t = 'lembur' and (coalesce((p->>'hours')::numeric, 0) <= 0 or (p->>'hours')::numeric > 12) then raise exception 'Jam lembur 0,5 sampai 12 jam.'; end if;
  if t = 'swap' then
    if partner is null or partner = me then raise exception 'Pilih rekan untuk tukar shift.'; end if;
    if not exists (select 1 from docs where col = 'staff' and id = partner and coalesce((data->>'active')::boolean, true)) then raise exception 'Rekan tidak ditemukan.'; end if;
    d2 := nullif(p->>'date2','')::date;
  end if;
  nid := to_char(now(), 'YYMMDD') || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  body := jsonb_build_object('type', t, 'sid', me, 'from', f::text, 'to', tt::text,
    'reason', left(coalesce(p->>'reason',''), 300), 'status', case when t = 'swap' then 'menunggu_rekan' else 'menunggu' end,
    'ts', (extract(epoch from now())*1000)::bigint);
  if t = 'lembur' then body := body || jsonb_build_object('hours', round((p->>'hours')::numeric * 2) / 2); end if;
  if t = 'sakit' and coalesce(p->>'photo','') <> '' then body := body || jsonb_build_object('photo', left(p->>'photo', 400)); end if;
  if t = 'swap' then body := body || jsonb_build_object('partner', partner) || case when d2 is not null then jsonb_build_object('date2', d2::text) else '{}'::jsonb end; end if;
  insert into docs (col, id, data) values ('requests', nid, body);
  return nid;
end $$;

create or replace function public.hr_cancel(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update docs set data = data || jsonb_build_object('status','batal','decidedAt',(extract(epoch from now())*1000)::bigint)
  where col = 'requests' and id = p_id and data->>'sid' = public.my_staff_id() and data->>'status' in ('menunggu','menunggu_rekan');
  if not found then raise exception 'Pengajuan tidak bisa dibatalkan.'; end if;
end $$;

create or replace function public.hr_partner(p_id text, p_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  update docs set data = data || jsonb_build_object('status', case when p_ok then 'menunggu' else 'ditolak_rekan' end, 'partnerAt', (extract(epoch from now())*1000)::bigint)
  where col = 'requests' and id = p_id and data->>'partner' = public.my_staff_id() and data->>'status' = 'menunggu_rekan';
  if not found then raise exception 'Permintaan tukar shift tidak ditemukan.'; end if;
end $$;

-- ubah satu sel jadwal shift/{bulan}.plan[tanggal][staf]
create or replace function public.hr_set_plan(p_date date, p_sid text, p_code text) returns void
language sql security definer set search_path = public as $$
  insert into docs (col, id, data) values ('shift', to_char(p_date,'YYYY-MM'),
    jsonb_build_object('month', to_char(p_date,'YYYY-MM'), 'plan', jsonb_build_object(p_date::text, jsonb_build_object(p_sid, p_code))))
  on conflict (col, id) do update set data = public.jsonb_deep_merge(docs.data,
    jsonb_build_object('plan', jsonb_build_object(p_date::text, jsonb_build_object(p_sid, p_code))))
$$;
create or replace function public.hr_get_plan(p_date date, p_sid text) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(data->'plan'->(p_date::text)->>p_sid, '') from docs where col = 'shift' and id = to_char(p_date,'YYYY-MM')
$$;

create or replace function public.hr_decide(p_id text, p_ok boolean, p_note text default '', p_code text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r jsonb; t text; s text; b text; d date; code text; ca text; cb text; q int; used int;
begin
  if not public.hr_is_approver() then raise exception 'Kamu tidak berwenang menyetujui pengajuan.'; end if;
  select data into r from docs where col = 'requests' and id = p_id for update;
  if r is null or r->>'status' <> 'menunggu' then raise exception 'Pengajuan sudah diproses atau belum siap disetujui.'; end if;
  if r->>'sid' = public.my_staff_id() then raise exception 'Pengajuan sendiri harus disetujui orang lain.'; end if;
  t := r->>'type'; s := r->>'sid';
  if p_ok then
    if t = 'cuti' then
      q := public.hr_quota(s, (r->>'from')::date); used := public.hr_cuti_used(s, extract(year from (r->>'from')::date)::int, p_id);
      if used + ((r->>'to')::date - (r->>'from')::date + 1) > q then raise exception 'Sisa cuti staf tidak cukup.'; end if;
    end if;
    if t in ('cuti','izin','sakit') then
      code := case t when 'cuti' then 'C' when 'izin' then 'I' else coalesce(nullif(p_code,''), case when r ? 'photo' then 'SK' else 'SX' end) end;
      if code not in ('C','I','SK','SX') then raise exception 'Kode tidak valid.'; end if;
      d := (r->>'from')::date;
      while d <= (r->>'to')::date loop perform public.hr_set_plan(d, s, code); d := d + 1; end loop;
    elsif t = 'swap' then
      b := r->>'partner';
      foreach d in array array_remove(array[(r->>'from')::date, nullif(r->>'date2','')::date], null) loop
        ca := public.hr_get_plan(d, s); cb := public.hr_get_plan(d, b);
        perform public.hr_set_plan(d, s, coalesce(cb, '')); perform public.hr_set_plan(d, b, coalesce(ca, ''));
      end loop;
    end if;
  end if;
  update docs set data = data || jsonb_build_object('status', case when p_ok then 'disetujui' else 'ditolak' end,
      'decidedBy', public.my_staff_id(), 'decidedAt', (extract(epoch from now())*1000)::bigint, 'note', left(coalesce(p_note,''), 200))
      || case when code is not null then jsonb_build_object('code', code) else '{}'::jsonb end
  where col = 'requests' and id = p_id;
end $$;

-- data Tim milik staf yang sedang masuk: pengajuan sendiri + permintaan tukar shift kepadanya, jatah cuti, nilai kinerja sendiri
create or replace function public.hr_mine() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me text := public.my_staff_id(); y int := extract(year from (now() at time zone 'Asia/Makassar'))::int;
begin
  if public.my_role() is null then raise exception 'Akun tidak aktif.'; end if;
  return jsonb_build_object(
    'requests', coalesce((select jsonb_agg(data || jsonb_build_object('id', id) order by id desc) from (
        select id, data from docs where col = 'requests' and (data->>'sid' = me or data->>'partner' = me) order by id desc limit 150) x), '[]'::jsonb),
    'quota', public.hr_quota(me, (now() at time zone 'Asia/Makassar')::date),
    'used', public.hr_cuti_used(me, y),
    'join', (select data->>'join' from docs where col = 'hrprofile' and id = me),
    'perf', coalesce((select jsonb_object_agg(id, data->'people'->me) from docs where col = 'perf' and data->'people' ? me), '{}'::jsonb));
end $$;

create or replace function public.hr_quiz(p_doc text, p_score int, p_n int) returns void
language plpgsql security definer set search_path = public as $$
declare me text := public.my_staff_id();
begin
  if public.my_role() is null then raise exception 'Akun tidak aktif.'; end if;
  if not exists (select 1 from docs where col = 'docs' and id = p_doc) then raise exception 'Materi tidak ditemukan.'; end if;
  if p_n < 0 or p_score < 0 or p_score > p_n then raise exception 'Nilai tidak valid.'; end if;
  insert into docs (col, id, data) values ('training', me, jsonb_build_object(p_doc, jsonb_build_object('score', p_score, 'n', p_n, 'ts', (extract(epoch from now())*1000)::bigint)))
  on conflict (col, id) do update set data = docs.data || jsonb_build_object(p_doc, jsonb_build_object('score', p_score, 'n', p_n, 'ts', (extract(epoch from now())*1000)::bigint));
end $$;

revoke execute on function public.hr_quota(text, date), public.hr_cuti_used(text, int, text), public.hr_set_plan(date, text, text), public.hr_get_plan(date, text) from anon, public, authenticated;
revoke execute on function public.hr_is_approver(), public.hr_request(jsonb), public.hr_cancel(text), public.hr_partner(text, boolean),
  public.hr_decide(text, boolean, text, text), public.hr_mine(), public.hr_quiz(text, int, int) from anon, public;
grant execute on function public.hr_is_approver(), public.hr_request(jsonb), public.hr_cancel(text), public.hr_partner(text, boolean),
  public.hr_decide(text, boolean, text, text), public.hr_mine(), public.hr_quiz(text, int, int) to authenticated;
