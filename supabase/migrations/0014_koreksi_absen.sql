-- 6 Nov 2026: pengajuan "Koreksi absen" (lupa check-out / gagal absen). Disetujui Owner atau Finance,
-- lalu server menulis jam ke attendance/{tanggal}.rec[staf] dengan tanda koreksi.
create or replace function public.hr_request(p jsonb) returns text
language plpgsql security definer set search_path = public as $$
declare
  me text := public.my_staff_id(); t text := p->>'type'; f date; tt date; d2 date; nid text; q int; used int;
  body jsonb; partner text := nullif(p->>'partner',''); tin text := nullif(p->>'tin',''); tout text := nullif(p->>'tout','');
begin
  if public.my_role() is null or me is null then raise exception 'Akun tidak aktif.'; end if;
  if t not in ('cuti','izin','sakit','swap','lembur','koreksi') then raise exception 'Jenis pengajuan tidak dikenal.'; end if;
  f := (p->>'from')::date; tt := coalesce(nullif(p->>'to','')::date, f);
  if f is null then raise exception 'Tanggal wajib diisi.'; end if;
  if tt < f or tt - f > 30 then raise exception 'Rentang tanggal maksimal 31 hari.'; end if;
  if t in ('swap','lembur','koreksi') then tt := f; end if;
  if t = 'koreksi' then
    if f > (now() at time zone 'Asia/Makassar')::date or f < (now() at time zone 'Asia/Makassar')::date - 14 then raise exception 'Koreksi absen hanya untuk 14 hari terakhir.'; end if;
    if tin is null and tout is null then raise exception 'Isi jam masuk atau jam pulang.'; end if;
    if (tin is not null and tin !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') or (tout is not null and tout !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then raise exception 'Format jam tidak valid.'; end if;
    if exists (select 1 from docs where col = 'requests' and data->>'sid' = me and data->>'type' = 'koreksi' and data->>'from' = f::text and data->>'status' = 'menunggu') then raise exception 'Sudah ada koreksi absen tanggal ini yang menunggu persetujuan.'; end if;
  end if;
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
  if t = 'koreksi' then body := body || jsonb_strip_nulls(jsonb_build_object('tin', tin, 'tout', tout)); end if;
  if t in ('sakit','koreksi') and coalesce(p->>'photo','') <> '' then body := body || jsonb_build_object('photo', left(p->>'photo', 400)); end if;
  if t = 'swap' then body := body || jsonb_build_object('partner', partner) || case when d2 is not null then jsonb_build_object('date2', d2::text) else '{}'::jsonb end; end if;
  insert into docs (col, id, data) values ('requests', nid, body);
  return nid;
end $$;

create or replace function public.hr_decide(p_id text, p_ok boolean, p_note text default '', p_code text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r jsonb; t text; s text; b text; d date; code text; ca text; cb text; q int; used int;
  cur jsonb; ins bigint; outs bigint; patch jsonb; me text := public.my_staff_id();
begin
  if not public.hr_is_approver() then raise exception 'Kamu tidak berwenang menyetujui pengajuan.'; end if;
  select data into r from docs where col = 'requests' and id = p_id for update;
  if r is null or r->>'status' <> 'menunggu' then raise exception 'Pengajuan sudah diproses atau belum siap disetujui.'; end if;
  if r->>'sid' = me then raise exception 'Pengajuan sendiri harus disetujui orang lain.'; end if;
  t := r->>'type'; s := r->>'sid';
  if t = 'koreksi' and public.my_role() not in ('owner','finance') then raise exception 'Koreksi absen hanya bisa disetujui Owner atau Finance.'; end if;
  if p_ok then
    if t = 'cuti' then
      q := public.hr_quota(s, (r->>'from')::date); used := public.hr_cuti_used(s, extract(year from (r->>'from')::date)::int, p_id);
      if used + ((r->>'to')::date - (r->>'from')::date + 1) > q then raise exception 'Sisa cuti staf tidak cukup.'; end if;
    end if;
    if t in ('cuti','izin','sakit') then
      code := case t when 'cuti' then 'C' when 'izin' then 'I' else 'SK' end;
      d := (r->>'from')::date;
      while d <= (r->>'to')::date loop perform public.hr_set_plan(d, s, code); d := d + 1; end loop;
    elsif t = 'swap' then
      b := r->>'partner';
      foreach d in array array_remove(array[(r->>'from')::date, nullif(r->>'date2','')::date], null) loop
        ca := public.hr_get_plan(d, s); cb := public.hr_get_plan(d, b);
        perform public.hr_set_plan(d, s, coalesce(cb, '')); perform public.hr_set_plan(d, b, coalesce(ca, ''));
      end loop;
    elsif t = 'koreksi' then
      select data->'rec'->s into cur from docs where col = 'attendance' and id = r->>'from';
      ins := case when r ? 'tin' then (extract(epoch from (((r->>'from') || ' ' || (r->>'tin'))::timestamp at time zone 'Asia/Makassar')) * 1000)::bigint
                  else nullif(cur->'in'->>'ts','')::bigint end;
      if ins is null then raise exception 'Belum ada jam masuk di tanggal itu. Minta staf mengisi jam masuk juga.'; end if;
      if r ? 'tout' then
        outs := (extract(epoch from (((r->>'from') || ' ' || (r->>'tout'))::timestamp at time zone 'Asia/Makassar')) * 1000)::bigint;
        if outs <= ins then outs := outs + 86400000; end if;
      end if;
      patch := jsonb_build_object('edit', jsonb_build_object('by', me, 'at', (extract(epoch from now())*1000)::bigint,
                 'reason', 'Pengajuan koreksi: ' || coalesce(r->>'reason',''), 'req', p_id,
                 'prevIn', cur->'in'->'ts', 'prevOut', cur->'out'->'ts'));
      if r ? 'tin' then patch := patch || jsonb_build_object('in', coalesce(cur->'in', jsonb_build_object('manual', true)) || jsonb_build_object('ts', ins, 'koreksi', p_id)); end if;
      if outs is not null then patch := patch || jsonb_build_object('out', coalesce(cur->'out', jsonb_build_object('manual', true)) || jsonb_build_object('ts', outs, 'koreksi', p_id)); end if;
      insert into docs (col, id, data) values ('attendance', r->>'from', jsonb_build_object('date', r->>'from', 'rec', jsonb_build_object(s, patch)))
      on conflict (col, id) do update set data = public.jsonb_deep_merge(docs.data, jsonb_build_object('rec', jsonb_build_object(s, patch)));
    end if;
  end if;
  update docs set data = data || jsonb_build_object('status', case when p_ok then 'disetujui' else 'ditolak' end,
      'decidedBy', me, 'decidedAt', (extract(epoch from now())*1000)::bigint, 'note', left(coalesce(p_note,''), 200))
      || case when code is not null then jsonb_build_object('code', code) else '{}'::jsonb end
  where col = 'requests' and id = p_id;
end $$;
