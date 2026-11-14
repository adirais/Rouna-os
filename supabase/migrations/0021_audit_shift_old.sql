-- 14 Nov 2026: "salin minggu lalu" tertekan dan menimpa jadwal 9-15 Nov; audit hanya mencatat tanggal yang berubah
-- (maks 6), bukan isi lamanya, sehingga jadwal asli tidak bisa dipulihkan. Untuk col 'shift' sekarang audit
-- menyimpan isi lama setiap tanggal yang berubah (tanpa batas 6), supaya kesalahan bisa dikembalikan persis.
create or replace function public.docs_audit() returns trigger language plpgsql security definer set search_path to 'public' as $function$
declare ch jsonb := '[]'::jsonb; k text; sub jsonb; oldv jsonb; lim int;
begin
  if coalesce(new.col, old.col) = 'stock' then return null; end if;
  lim := case when coalesce(new.col, old.col) = 'shift' then 1000 else 6 end;
  if tg_op = 'UPDATE' then
    for k in select jsonb_object_keys(new.data) union select jsonb_object_keys(old.data) loop
      if (old.data->k) is distinct from (new.data->k) then
        if jsonb_typeof(new.data->k) = 'object' and jsonb_typeof(old.data->k) = 'object' then
          select coalesce(jsonb_agg(s), '[]'::jsonb) into sub from (
            select s from (select jsonb_object_keys(new.data->k) s union select jsonb_object_keys(old.data->k)) x
            where (old.data->k->s) is distinct from (new.data->k->s) limit lim) y;
          if new.col = 'shift' then
            select coalesce(jsonb_object_agg(s #>> '{}', coalesce(old.data->k->(s #>> '{}'), 'null'::jsonb)), '{}'::jsonb) into oldv from jsonb_array_elements(sub) s;
            ch := ch || jsonb_build_object('k', k, 'sub', sub, 'old', oldv);
          else
            ch := ch || jsonb_build_object('k', k, 'sub', sub);
          end if;
        else
          ch := ch || jsonb_build_object('k', k);
        end if;
      end if;
    end loop;
    if ch = '[]'::jsonb then return null; end if;
  end if;
  insert into public.audit(user_id, staff_id, op, col, doc_id, changes)
  values (auth.uid(), (select staff_id from public.profiles where user_id = auth.uid()), tg_op, coalesce(new.col, old.col), coalesce(new.id, old.id), ch);
  return null;
end $function$;
revoke execute on function public.docs_audit() from public, anon, authenticated;
