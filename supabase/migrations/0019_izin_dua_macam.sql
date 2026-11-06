-- 6 Nov 2026: izin dua macam. Penyetuju memilih I (izin dicover: berduka, musibah; tidak dipotong)
-- atau IX (izin tidak dicover; dipotong per hari, bukan alpha).
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
      code := case t when 'cuti' then 'C' when 'izin' then case when p_code = 'IX' then 'IX' else 'I' end else 'SK' end;
      d := (r->>'from')::date;
      while d <= (r->>'to')::date loop perform public.hr_set_plan(d, s, code); d := d + 1; end loop;
    elsif t = 'swap' then
      b := r->>'partner';
      foreach d in array array_remove(array[(r->>'from')::date, nullif(r->>'date2','')::date], null) loop
        ca := public.hr_get_plan(d, s); cb := public.hr_get_plan(d, b);
        perform public.hr_set_plan(d, s, coalesce(cb, '')); perform public.hr_set_plan(d, b, coalesce(ca, ''));
      end loop;
    elsif t = 'ganti' then
      perform public.hr_set_plan((r->>'from')::date, s, r->>'code');
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
      || case when code is not null and t <> 'ganti' then jsonb_build_object('code', code) else '{}'::jsonb end
  where col = 'requests' and id = p_id;
end $$;
