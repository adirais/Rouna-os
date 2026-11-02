-- 2 Nov 2026: setiap catatan mutasi stok (ambil, masuk, retur, waste, opname) selalu dicap akun yang menyimpannya.
-- Server yang mengisi `by` dari akun yang login, jadi tidak bisa diisi atas nama orang lain dari aplikasi.
create or replace function public.moves_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text; v jsonb; me text := public.my_staff_id(); oldl jsonb; newl jsonb;
begin
  if new.col <> 'moves' or me is null then return new; end if;
  oldl := case when tg_op = 'UPDATE' then coalesce(old.data->'list', '{}'::jsonb) else '{}'::jsonb end;
  newl := coalesce(new.data->'list', '{}'::jsonb);
  for k, v in select * from jsonb_each(newl) loop
    if not oldl ? k then newl := jsonb_set(newl, array[k], v || jsonb_build_object('by', me)); end if;
  end loop;
  new.data := jsonb_set(new.data, '{list}', newl);
  return new;
end $$;

drop trigger if exists docs_moves_stamp on public.docs;
create trigger docs_moves_stamp before insert or update on public.docs
for each row when (new.col = 'moves') execute function public.moves_stamp();
