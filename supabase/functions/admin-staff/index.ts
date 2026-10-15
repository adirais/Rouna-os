// ROUNA OS — staff accounts (bootstrap first owner, create/update staff logins)
// verify_jwt is off because first-time setup runs before anyone is signed in;
// every other action checks the caller's session and role below.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DOMAIN = "rounaos.app";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (msg: string, status = 400) => json({ error: msg }, status);
const email = (u: string) => `${u}@${DOMAIN}`;
const pw = (p: string) => `rouna-${p}`;
const okUser = (u: string) => /^[a-z0-9._-]{3,24}$/.test(u);
const okPin = (p: string) => /^\d{6}$/.test(p);
const newId = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const ROLES = ["owner", "manager", "finance", "headbar", "kitchen", "gudang", "crew"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail("method", 405);
  const admin = createClient(URL, SR, { auth: { persistSession: false, autoRefreshToken: false } });
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return fail("Body tidak valid."); }
  const action = String(body.action || "");

  const getStaff = async (id: string) => (await admin.from("docs").select("data").eq("col", "staff").eq("id", id).maybeSingle()).data?.data as Record<string, unknown> | undefined;
  const putStaff = async (id: string, data: Record<string, unknown>) => {
    const { error } = await admin.from("docs").upsert({ col: "staff", id, data });
    if (error) throw error;
  };
  const usernameTaken = async (u: string, staffId: string) => {
    const { data } = await admin.from("profiles").select("staff_id").eq("username", u).maybeSingle();
    return !!data && data.staff_id !== staffId;
  };

  try {
    if (action === "bootstrap") {
      const { count } = await admin.from("profiles").select("user_id", { count: "exact", head: true });
      if ((count || 0) > 0) return fail("Akun pertama sudah dibuat. Masuk dengan username dan PIN.", 403);
      const username = String(body.username || "").trim().toLowerCase(), pin = String(body.pin || ""), name = String(body.name || "").trim().slice(0, 40);
      if (!okUser(username)) return fail("Username 3–24 karakter: huruf kecil, angka, titik, strip.");
      if (!okPin(pin)) return fail("PIN harus 6 angka.");
      // link to the existing owner record if there is one (data carried over from the old app)
      const { data: owners } = await admin.from("docs").select("id,data").eq("col", "staff").eq("data->>role", "owner");
      const existing = (owners || [])[0];
      const staffId = existing?.id || newId();
      const { data: u, error } = await admin.auth.admin.createUser({ email: email(username), password: pw(pin), email_confirm: true });
      if (error) return fail(error.message);
      await admin.from("profiles").insert({ user_id: u.user.id, staff_id: staffId, username });
      const prev = existing?.data || { createdAt: Date.now() };
      await putStaff(staffId, { ...prev, name: name || prev.name || "Owner", role: "owner", active: true, username });
      return json({ ok: true, staffId });
    }

    // everything else needs a signed-in Owner or Manager
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: who } = await admin.auth.getUser(token);
    if (!who?.user) return fail("Sesi habis. Masuk lagi.", 401);
    const { data: prof } = await admin.from("profiles").select("staff_id").eq("user_id", who.user.id).maybeSingle();
    const me = prof ? await getStaff(prof.staff_id) : undefined;
    const myRole = me && me.active !== false ? String(me.role) : "";
    if (!["owner", "manager"].includes(myRole)) return fail("Hanya Owner atau Manager yang bisa mengatur staf.", 403);

    if (action === "save") {
      const staffId = String(body.staffId || "") || newId();
      const prev = (await getStaff(staffId)) || {};
      const name = String(body.name || "").trim().slice(0, 40);
      const role = String(body.role || "crew");
      const active = body.active !== false;
      const username = String(body.username || "").trim().toLowerCase();
      const pin = String(body.pin || "");
      if (!name) return fail("Nama wajib diisi.");
      if (!ROLES.includes(role)) return fail("Peran tidak dikenal.");
      if ((role === "owner" || prev.role === "owner") && myRole !== "owner") return fail("Hanya Owner yang bisa mengatur akun Owner.", 403);
      if (username && !okUser(username)) return fail("Username 3–24 karakter: huruf kecil, angka, titik, strip.");
      if (pin && !okPin(pin)) return fail("PIN harus 6 angka.");
      if (username && await usernameTaken(username, staffId)) return fail("Username sudah dipakai staf lain.");

      // keep at least one active owner/manager
      if (["owner", "manager"].includes(String(prev.role)) && prev.active !== false && (!["owner", "manager"].includes(role) || !active)) {
        const { data: all } = await admin.from("docs").select("id,data").eq("col", "staff");
        const left = (all || []).filter((s) => s.id !== staffId && ["owner", "manager"].includes(s.data?.role) && s.data?.active !== false);
        if (!left.length) return fail("Harus ada minimal satu Owner atau Manager aktif.");
      }

      const { data: link } = await admin.from("profiles").select("user_id,username").eq("staff_id", staffId).maybeSingle();
      if (link) {
        const upd: Record<string, unknown> = {};
        if (username && username !== link.username) upd.email = email(username);
        if (pin) upd.password = pw(pin);
        upd.ban_duration = active ? "none" : "876000h";
        const { error } = await admin.auth.admin.updateUserById(link.user_id, upd);
        if (error) return fail(error.message);
        if (username && username !== link.username) await admin.from("profiles").update({ username }).eq("user_id", link.user_id);
      } else if (username) {
        if (!pin) return fail("Isi PIN 6 angka untuk akun baru.");
        const { data: u, error } = await admin.auth.admin.createUser({ email: email(username), password: pw(pin), email_confirm: true, ban_duration: active ? "none" : "876000h" });
        if (error) return fail(error.message);
        await admin.from("profiles").insert({ user_id: u.user.id, staff_id: staffId, username });
      }
      await putStaff(staffId, { ...prev, name, role, active, username: username || prev.username || "", createdAt: prev.createdAt || Date.now() });
      return json({ ok: true, staffId });
    }
    return fail("Aksi tidak dikenal.");
  } catch (e) {
    console.error(e);
    return fail("Server error: " + (e instanceof Error ? e.message : String(e)), 500);
  }
});
