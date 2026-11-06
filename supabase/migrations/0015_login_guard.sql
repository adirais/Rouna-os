-- 6 Nov 2026: batas salah PIN. Hanya edge function `login` (service role) yang membaca/menulis tabel ini.
create table if not exists public.login_guard (
  username text primary key,
  fails int not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.login_guard enable row level security;
-- kunci rahasia untuk menurunkan password dari PIN (disimpan di tabel server-only `secrets`)
insert into public.secrets (key, value) values ('pin_pepper', to_jsonb(encode(extensions.gen_random_bytes(32), 'hex')))
on conflict (key) do nothing;

-- Foto privat: bucket photos tidak lagi publik; akun aktif bisa membaca lewat tautan bertanda tangan.
drop policy if exists photos_read on storage.objects;
create policy photos_read on storage.objects for select to authenticated using (bucket_id = 'photos' and public.my_role() is not null);
-- (bucket diubah ke private setelah aplikasi versi baru live: update storage.buckets set public = false where id = 'photos';)

-- 0016: PIN diverifikasi di server (HMAC dengan pin_pepper). Password Supabase Auth diganti acak,
-- sesi dibuat lewat magic-link token sekali pakai yang ditukar di HP (bukan login password dari server).
create table if not exists public.login_pin (
  user_id uuid primary key,
  h text not null,
  updated_at timestamptz not null default now()
);
alter table public.login_pin enable row level security;
