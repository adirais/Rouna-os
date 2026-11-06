// ROUNA OS — login dengan username + PIN, dengan batas salah PIN (6 Nov 2026).
// PIN diperiksa di server (HMAC dengan kunci rahasia, tabel login_pin). Password Supabase Auth diganti acak,
// jadi PIN tidak bisa ditebak langsung ke Supabase Auth; semua percobaan lewat fungsi ini yang mengunci
// akun 15 menit setelah 5x salah (60 menit setelah 10x). Sesi dibuat dengan token magic-link sekali pakai
// yang ditukar di HP. Akun lama (password "rouna-PIN") dipindahkan otomatis saat login pertama.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const DOMAIN = "rounaos.app";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (msg: string, status = 400, extra: Record<string, unknown> = {}) => json({ error: msg, ...extra }, status);
const admin = createClient(URL, SR, { auth: { persistSession: false, autoRefreshToken: false } });
const MAX = 5;

async function pinHash(userId: string, pin: string) {
  const pep = (await admin.from("secrets").select("value").eq("key", "pin_pepper").maybeSingle()).data?.value as string | undefined;
  if (!pep) throw new Error("pin_pepper belum diatur");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(pep), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(userId + ":" + pin)));
  return Array.from(sig).map((b) => b.toString(16).padStart(2, "0")).join("");
}
const randomPw = () => "X" + Array.from(crypto.getRandomValues(new Uint8Array(24))).map((b) => b.toString(16).padStart(2, "0")).join("");
const same = (a: string, b: string) => { if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("method", 405);
  let body: Record<string, unknown>; try { body = await req.json(); } catch { return fail("Body tidak valid."); }
  const username = String(body.username || "").trim().toLowerCase(), pin = String(body.pin || "");
  if (!/^[a-z0-9._-]{3,24}$/.test(username) || !/^\d{6}$/.test(pin)) return fail("Username atau PIN salah.", 401);
  try {
    // percobaan dihitung atomik sebelum PIN diperiksa (aman terhadap percobaan paralel)
    const { data: at, error: ae } = await admin.rpc("login_attempt", { p_user: username, p_max: MAX });
    if (ae) throw ae;
    const g = Array.isArray(at) ? at[0] : at;
    if (!g?.allowed) {
      const m = Math.max(1, Math.ceil((new Date(g.locked_until).getTime() - Date.now()) / 60000));
      return fail(`Terlalu banyak PIN salah. Akun terkunci ${m} menit lagi, atau minta Owner/Manager mengganti PIN.`, 429, { locked: m });
    }
    const email = `${username}@${DOMAIN}`;
    const { data: prof } = await admin.from("profiles").select("user_id").eq("username", username).maybeSingle();
    let ok = false;
    if (prof) {
      const h = await pinHash(prof.user_id, pin);
      const { data: rec } = await admin.from("login_pin").select("h").eq("user_id", prof.user_id).maybeSingle();
      if (rec) ok = same(rec.h, h);
      else {
        // akun lama: cek sekali dengan password lama, lalu pindahkan
        const c = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
        const r = await c.auth.signInWithPassword({ email, password: "rouna-" + pin });
        if (r.error && /banned/i.test(r.error.message)) return fail("Akun ini dinonaktifkan.", 403);
        if (!r.error) {
          ok = true;
          await admin.from("login_pin").upsert({ user_id: prof.user_id, h, updated_at: new Date().toISOString() });
          await admin.auth.admin.updateUserById(prof.user_id, { password: randomPw() });
        }
      }
    }
    if (!ok) {
      const inCycle = g.fails % (MAX + 1), left = MAX - inCycle;
      if (left <= 0) { const { data: l } = await admin.rpc("login_attempt", { p_user: username, p_max: MAX }); const x = Array.isArray(l) ? l[0] : l;
        const m = x?.locked_until ? Math.max(1, Math.round((new Date(x.locked_until).getTime() - Date.now()) / 60000)) : 15;
        return fail(`PIN salah ${MAX}x. Akun dikunci ${m} menit, atau minta Owner/Manager mengganti PIN.`, 429, { locked: m }); }
      return fail(`Username atau PIN salah. Sisa ${left} percobaan sebelum dikunci.`, 401, { left });
    }
    const { data: u } = await admin.auth.admin.getUserById(prof!.user_id);
    const bu = (u?.user as Record<string, unknown> | undefined)?.banned_until as string | undefined;
    if (bu && new Date(bu).getTime() > Date.now()) return fail("Akun ini dinonaktifkan.", 403);
    await admin.from("login_guard").delete().eq("username", username);
    const { data: link, error } = await admin.auth.admin.generateLink({ type: "magiclink", email });
    if (error || !link?.properties?.hashed_token) return fail("Gagal membuat sesi: " + (error?.message || "token kosong"), 500);
    return json({ ok: true, token_hash: link.properties.hashed_token });
  } catch (e) {
    console.error(e);
    return fail("Server error: " + (e instanceof Error ? e.message : String(e)), 500);
  }
});
