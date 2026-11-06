-- 6 Nov 2026: hitung percobaan login secara atomik SEBELUM PIN diperiksa (dipanggil edge function `login`).
-- Percobaan ke-6, 12, 18, ... mengunci akun: 15 menit pertama kali, 60 menit berikutnya. Login berhasil menghapus baris.
create or replace function public.login_attempt(p_user text, p_max int default 5) returns table(fails int, locked_until timestamptz, allowed boolean)
language plpgsql security definer set search_path = public as $$
declare g login_guard;
begin
  insert into login_guard as lg (username, fails, locked_until, updated_at) values (p_user, 1, null, now())
  on conflict (username) do update set
    fails = case when lg.locked_until is not null and lg.locked_until > now() then lg.fails else lg.fails + 1 end,
    updated_at = now()
  returning * into g;
  if g.locked_until is not null and g.locked_until > now() then
    return query select g.fails, g.locked_until, false; return;
  end if;
  if g.fails % (p_max + 1) = 0 then
    update login_guard set locked_until = now() + case when g.fails > p_max + 1 then interval '60 minutes' else interval '15 minutes' end
    where username = p_user returning * into g;
    return query select g.fails, g.locked_until, false; return;
  end if;
  return query select g.fails, g.locked_until, true;
end $$;
revoke execute on function public.login_attempt(text, int) from public, anon, authenticated;
grant execute on function public.login_attempt(text, int) to service_role;
