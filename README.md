# ROUNA OS — versi Web

Aplikasi operasional Coffee Rouna yang berdiri sendiri: staf masuk dengan **username + PIN 6 angka**, tanpa akun Claude. Data tersimpan di Supabase dan dijaga per peran langsung di database.

## Yang sudah siap

| Bagian | Status |
|---|---|
| Proyek Supabase `rouna-os` (Singapura) | Sudah dibuat |
| Database + aturan keamanan per peran | Sudah terpasang |
| Fungsi server `admin-staff` (akun staf) dan `ai` (analisis) | Sudah aktif |
| Data Owner (Adi Rais) dan pengaturan dasar | Sudah masuk |
| Data lain (146 bahan, 37 resep, SOP, keuangan Jul–Sep, dll.) | Diimpor lewat aplikasi, lihat Langkah 4 |
| Tampilan web (folder `public/`) | Siap dipasang di Vercel |

## Siapa bisa melihat apa

| Data | Yang bisa melihat dan mengubah |
|---|---|
| Kas harian | Owner, Manager, Finance, Headbar |
| Pengeluaran, gaji, brief pagi | Owner, Manager, Finance |
| Pengaturan (target food cost, dll.) | Diubah oleh Owner, Manager, Finance |
| Resep/menu dan dokumen SOP | Diubah oleh Owner dan Manager (semua staf bisa membaca) |
| Akun staf | Hanya lewat Pengaturan → Staf oleh Owner/Manager. Akun Owner hanya bisa diatur Owner |
| Stok, order, closing, absensi, waste | Semua staf aktif |

Staf yang dinonaktifkan langsung kehilangan akses.

---

## Langkah 1: Matikan pendaftaran bebas di Supabase (2 menit)

1. Buka https://supabase.com/dashboard dan pilih proyek **rouna-os**.
2. Buka **Authentication → Sign In / Providers**.
3. Matikan **Allow new users to sign up**, lalu simpan.

Akun staf tetap bisa dibuat dari dalam aplikasi, karena pembuatannya lewat fungsi server.

## Langkah 2: Pasang web di Vercel (10 menit)

Cara termudah tanpa coding adalah lewat GitHub:

1. Buat akun di https://github.com, lalu klik **New repository**. Beri nama `rouna-os` dan pilih **Private**.
2. Di repo baru, klik **uploading an existing file**. Seret **isi** folder ini (`public/`, `supabase/`, `vercel.json`, `README.md`), lalu klik **Commit changes**.
3. Buat akun di https://vercel.com dengan **Continue with GitHub**.
4. Klik **Add New → Project**, pilih repo `rouna-os`, lalu klik **Import**.
5. Biarkan Framework Preset **Other**, jangan isi apa-apa lagi, lalu klik **Deploy**.
6. Setelah selesai, kamu mendapat alamat seperti `rouna-os.vercel.app`. ROUNA OS sudah bisa dibuka dari sini.

Setiap kali file di GitHub diubah, Vercel otomatis memasang versi baru.

## Langkah 3: Masuk pertama kali

1. Buka alamat web tadi. Karena belum ada akun, muncul layar **Buat akun Owner**.
2. Isi nama, username (misalnya `adi`), dan PIN 6 angka. Akun ini otomatis tersambung ke data Owner "Adi Rais" yang sudah ada.

## Langkah 4: Pindahkan data dari ROUNA OS lama

1. Buka **Pengaturan → Umum → Cadangan data → Pulihkan dari file**.
2. Pilih file `rouna-data-awal.json`. File ini dikirim terpisah dan berisi data dari versi Claude per 15 Okt 2026.
3. Konfirmasi. Sebanyak 202 dokumen akan masuk: bahan, resep, SOP, laporan harian, kas, pengeluaran, dan total gaji.

Simpan file itu di tempat aman, karena isinya data keuangan.

> Jika ada transaksi baru yang dicatat di versi Claude setelah 15 Okt, minta Claude mengekspor ulang sebelum kamu pindah penuh.

## Langkah 5: Tambah akun staf

**Pengaturan → Staf → Tambah staf**: isi nama, peran, username, dan PIN 6 angka. Beri tahu PIN ke staf secara langsung, jangan lewat grup.

Di HP staf:

- buka alamat web, masuk sekali, lalu pilih **Add to Home Screen** (iPhone: tombol Share; Android: menu ⋮);
- ROUNA OS akan tampil seperti aplikasi, lengkap dengan ikon Rouna;
- nama staf diingat di HP itu, jadi berikutnya cukup ketuk nama lalu masukkan PIN.

## Langkah 6 (opsional): Aktifkan analisis AI

Tombol "Analisis mendalam" di Analitik butuh API key Anthropic (berbayar per pemakaian):

1. Buat key di https://console.anthropic.com.
2. Di Supabase, buka **Edge Functions → Secrets → Add secret**. Isi Name `ANTHROPIC_API_KEY` dan Value key tadi.

Tanpa langkah ini, semua fitur lain tetap jalan dan tombol AI hanya menampilkan pesan bahwa fitur belum aktif.

---

## Beli dan pasang domain sendiri

### 1. Pilih nama

Disarankan memakai subdomain dari domain utama Rouna, misalnya `os.coffeerouna.com`. Domain utamanya tetap bisa dipakai untuk website publik, dan ROUNA OS menempati subdomain `os.`.

### 2. Beli domain

| Jenis | Tempat beli | Catatan |
|---|---|---|
| `.com` | Cloudflare Registrar, Namecheap, Porkbun | Harga transparan, perpanjangan tidak naik drastis di Cloudflare |
| `.id` / `.co.id` / `.my.id` | Registrar lokal, misalnya Domainesia atau Niagahoster/Hostinger ID | `.co.id` butuh dokumen usaha (NIB/akta). `.id` dan `.my.id` cukup KTP |

Saat membeli:

- bandingkan **harga perpanjangan**, bukan hanya harga tahun pertama;
- aktifkan **auto-renew** agar domain tidak hilang;
- hosting, email, atau paket tambahan tidak perlu dibeli. Yang dibutuhkan hanya domainnya.

### 3. Sambungkan ke Vercel

1. Di Vercel, buka proyek **rouna-os → Settings → Domains**. Ketik `os.namadomainmu.com`, lalu klik **Add**.
2. Vercel menampilkan satu record DNS, biasanya **CNAME** dengan nilai seperti `cname.vercel-dns.com` atau alamat khusus proyek. **Salin persis nilai yang ditampilkan Vercel.**
3. Di registrar, buka menu **DNS / Kelola DNS**, lalu tambah record:
   - Type: `CNAME`
   - Name/Host: `os`
   - Value/Target: nilai dari Vercel
   - Jika memakai Cloudflare: set Proxy status ke **DNS only** (awan abu-abu).
4. Tunggu beberapa menit sampai beberapa jam. Vercel menandai domain **Valid** dan memasang HTTPS otomatis.
5. Di Supabase, buka **Authentication → URL Configuration**, lalu isi Site URL dengan `https://os.namadomainmu.com`.

---

## Perawatan

- **Cadangan mingguan**: Pengaturan → Umum → **Unduh cadangan**. Paket gratis Supabase tidak menyimpan riwayat backup yang bisa dipulihkan sendiri.
- **Paket gratis Supabase** akan dijeda jika tidak dipakai sekitar seminggu. Selama outlet memakainya setiap hari, ini tidak terjadi. Jika sempat terjeda, buka dashboard Supabase lalu klik **Restore**.
- **PIN** cukup kuat untuk pemakaian internal karena Supabase membatasi percobaan login berulang. Gunakan PIN yang tidak mudah ditebak, jangan 123456 atau tanggal lahir.

## Isi folder

```
public/                 ← web yang dipasang Vercel
  index.html            ← seluruh aplikasi
  config.js             ← alamat Supabase + anon key (aman untuk publik)
  manifest.webmanifest, sw.js, assets/  ← ikon & logo Rouna, mode aplikasi HP
supabase/
  migrations/0001_rouna_core.sql   ← struktur database + aturan keamanan (sudah terpasang)
  functions/admin-staff, functions/ai  ← fungsi server (sudah aktif)
vercel.json             ← pengaturan hosting
```
