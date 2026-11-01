-- 1 Nov 2026: izin mendadak & sakit yang diajukan dan disetujui tidak dipotong dan tidak dihitung alpha.
-- Persetujuan sakit selalu dicatat SK (bukan lagi SX bila tanpa foto surat). SX tetap bisa diisi manual di Jadwal
-- untuk sakit tanpa pengajuan.
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
      code := case t when 'cuti' then 'C' when 'izin' then 'I' else 'SK' end;
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
