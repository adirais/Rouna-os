# ROUNA OS

Aplikasi operasional internal Coffee Rouna: stok, order bahan, closing, menu & COGS, penjualan, analitik, keuangan, SOP, dan absensi.

**Alamat:** https://rouna.coffee (cadangan: https://adirais.github.io/Rouna-os/)

Staf masuk dengan **username + PIN 6 angka**. Data tersimpan di Supabase (proyek `rouna-os`, Singapura) dan dijaga per peran langsung di database.

## Cara kerja

| Bagian | Di mana |
|---|---|
| Halaman web (file di repo ini) | GitHub Pages, branch `main`, folder root |
| Data, login, foto | Supabase `rouna-os` |
| Fungsi server `admin-staff` (akun staf) & `ai` (analisis) | Supabase Edge Functions — kodenya di `supabase/functions/` |
| Struktur database & aturan keamanan | `supabase/migrations/0001_rouna_core.sql` (sudah terpasang) |

Setiap perubahan yang di-commit ke `main` tayang otomatis dalam 1–2 menit.

## Siapa bisa melihat apa

| Data | Akses |
|---|---|
| Kas harian | Owner, Manager, Finance, Headbar |
| Pengeluaran, gaji, brief pagi | Owner, Manager, Finance |
| Pengaturan (target food cost, dll.) | Diubah oleh Owner, Manager, Finance |
| Resep/menu & dokumen SOP | Diubah oleh Owner & Manager; semua staf bisa membaca |
| Akun staf | Pengaturan → Staf (Owner/Manager). Akun Owner hanya diatur Owner |
| Stok, order, closing, absensi, waste | Semua staf aktif |

Staf yang dinonaktifkan langsung kehilangan akses.

## Menambah staf

Pengaturan → Staf → Tambah staf: nama, peran, username, PIN 6 angka. Beri tahu PIN langsung ke staf. Di HP staf: buka alamat web → masuk → **Add to Home Screen** (iPhone: tombol Share; Android: menu ⋮).

## Aktifkan analisis AI (opsional)

Buat API key di https://console.anthropic.com, lalu di Supabase → Edge Functions → Secrets tambahkan `ANTHROPIC_API_KEY`.

## Pakai domain sendiri

1. Beli domain (mis. `coffeerouna.com`) di Cloudflare Registrar, Namecheap, atau registrar lokal (`.id` cukup KTP; `.co.id` butuh dokumen usaha). Bandingkan harga **perpanjangan** dan nyalakan auto-renew.
2. Di registrar → DNS, tambah record **CNAME**: Name `os`, Value `adirais.github.io`.
3. Di repo ini → Settings → Pages → Custom domain: isi `os.coffeerouna.com` → Save, lalu centang **Enforce HTTPS** setelah tersedia.
4. Di Supabase → Authentication → URL Configuration → Site URL: isi alamat baru.

## Perawatan

- **Cadangan mingguan:** Pengaturan → Umum → Unduh cadangan (khusus Owner). Paket gratis Supabase tidak menyediakan pemulihan riwayat.
- **Paket gratis Supabase** dijeda bila tidak dipakai sekitar seminggu; pemakaian harian mencegahnya. Jika terjeda: dashboard Supabase → Restore.
- **Jangan unggah file data** (`rouna-data-awal.json` atau file cadangan) ke repo ini — repo ini publik.

## Isi repo

```
index.html              seluruh aplikasi
config.js               alamat Supabase + anon key (boleh publik; data dijaga login + RLS)
manifest.webmanifest    mode aplikasi di HP
sw.js                   service worker minimal (tanpa cache, data selalu terbaru)
assets/                 logo, mark, dan ikon Rouna
supabase/               fungsi server & migrasi database (arsip, tidak dipakai GitHub Pages)
```
