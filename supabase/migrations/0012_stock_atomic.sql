-- 6 Nov 2026: perubahan stok dihitung di server secara atomik (baris dikunci), bukan menimpa angka dari HP.
-- Sebelumnya HP menulis angka akhir gudang+area dari data lokalnya; HP yang datanya basi (aplikasi terbuka lama,
-- sinyal putus) atau dua orang yang menyimpan bersamaan bisa saling menimpa stok.
-- p_dg / p_da = tambahan (boleh minus) untuk gudang / area. p_gudang / p_area = set angka pasti (opname, closing).
create or replace function public.stock_apply(p_id text, p_dg numeric default 0, p_da numeric default 0,
  p_gudang numeric default null, p_area numeric default null) returns jsonb
language plpgsql set search_path = public as $$
declare cur jsonb; g numeric; a numeric; nxt jsonb;
begin
  if not public.can_write('stock') then raise exception 'Kamu tidak berwenang mengubah stok.'; end if;
  select data into cur from docs where col = 'stock' and id = p_id for update;
  g := coalesce((cur->>'gudang')::numeric, 0); a := coalesce((cur->>'area')::numeric, 0);
  g := round(coalesce(p_gudang, g + coalesce(p_dg, 0)), 3);
  a := round(coalesce(p_area, a + coalesce(p_da, 0)), 3);
  nxt := coalesce(cur, '{}'::jsonb) || jsonb_build_object('gudang', g, 'area', a,
    'updatedAt', (extract(epoch from now()) * 1000)::bigint, 'by', public.my_staff_id());
  insert into docs (col, id, data) values ('stock', p_id, nxt)
  on conflict (col, id) do update set data = excluded.data;
  return nxt;
end $$;
revoke execute on function public.stock_apply(text, numeric, numeric, numeric, numeric) from public, anon;
grant execute on function public.stock_apply(text, numeric, numeric, numeric, numeric) to authenticated;

-- Fungsi trigger tidak perlu bisa dipanggil lewat API (saran Supabase advisor).
revoke execute on function public.docs_audit() from public, anon, authenticated;
revoke execute on function public.moves_stamp() from public, anon, authenticated;

-- Closing: set sisa area banyak bahan sekaligus dalam satu panggilan.
create or replace function public.stock_set_area_many(p jsonb) returns integer
language plpgsql set search_path = public as $$
declare k text; v jsonb; n int := 0;
begin
  if not public.can_write('stock') then raise exception 'Kamu tidak berwenang mengubah stok.'; end if;
  for k, v in select * from jsonb_each(coalesce(p, '{}'::jsonb)) loop
    perform public.stock_apply(k, 0, 0, null, (v #>> '{}')::numeric); n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.stock_set_area_many(jsonb) from public, anon;
grant execute on function public.stock_set_area_many(jsonb) to authenticated;
