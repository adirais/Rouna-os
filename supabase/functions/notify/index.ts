// ROUNA OS — notifications via Telegram and/or WhatsApp (Fonnte): morning summary, midday stock/order alert, closing reminder
// verify_jwt is off: the app calls it with the user's session (checked below, Owner/Manager only),
// and pg_cron calls it with a private key stored in public.secrets.
import { createClient } from "npm:@supabase/supabase-js@2";

const URL = Deno.env.get("SUPABASE_URL")!;
const SR = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (msg: string, status = 400) => json({ error: msg }, status);
type Doc = Record<string, any>;

const admin = createClient(URL, SR, { auth: { persistSession: false, autoRefreshToken: false } });
const getSecret = async (k: string) => (await admin.from("secrets").select("value").eq("key", k).maybeSingle()).data?.value;
const setSecret = async (k: string, v: unknown) => { await admin.from("secrets").upsert({ key: k, value: v, updated_at: new Date().toISOString() }); };

// ---- dates in Makassar time (UTC+8) ----
const wita = (d = new Date()) => new Date(d.getTime() + 8 * 3600e3);
const ymd = (d: Date) => d.toISOString().slice(0, 10);
const todayW = () => ymd(wita());
const addDays = (s: string, n: number) => { const d = new Date(s + "T12:00:00Z"); d.setUTCDate(d.getUTCDate() + n); return ymd(d); };
const HARI = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"], BLN = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];
const fdate = (s: string) => { const d = new Date(s + "T12:00:00Z"); return `${HARI[d.getUTCDay()]}, ${d.getUTCDate()} ${BLN[d.getUTCMonth()]}`; };
const rp = (n: number) => "Rp " + Math.round(n || 0).toLocaleString("id-ID");
const pct = (n: number) => (n * 100).toLocaleString("id-ID", { maximumFractionDigits: 0 }) + "%";
const esc = (s: unknown) => String(s ?? "").replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]!));

async function col(c: string): Promise<Doc[]> {
  const { data } = await admin.from("docs").select("id,data").eq("col", c).limit(5000);
  return (data || []).map((r) => ({ id: r.id, ...r.data }));
}
async function one(c: string, id: string): Promise<Doc | null> {
  const { data } = await admin.from("docs").select("data").eq("col", c).eq("id", id).maybeSingle();
  return data?.data || null;
}

async function compose(kind: string): Promise<string | null> {
  const t = todayW(), y = addDays(t, -1), mo = t.slice(0, 7);
  const [items, stock, orders, settings] = await Promise.all([col("items"), col("stock"), col("orders"), one("settings", "app")]);
  const st: Record<string, Doc> = Object.fromEntries(stock.map((s) => [s.id, s]));
  const active = items.filter((i) => i.active !== false);
  const low = active.filter((i) => +i.min > 0 && (+st[i.id]?.gudang || 0) <= +i.min).sort((a, b) => (+st[a.id]?.gudang || 0) - (+st[b.id]?.gudang || 0));
  const out = low.filter((i) => (+st[i.id]?.gudang || 0) <= 0);
  const waitApprove = orders.filter((o) => o.status === "diajukan").length;
  const waitRecv = orders.filter((o) => o.status === "disetujui" || o.status === "dipesan").length;
  const L: string[] = [];

  if (kind === "closing") {
    const cl = await one("closings", t);
    const miss = ["bar", "kitchen"].filter((a) => !cl?.shifts?.[a]).map((a) => a === "bar" ? "Bar" : "Kitchen");
    if (!miss.length) return null;
    return `⚠️ <b>Closing ${fdate(t)} belum dikirim</b>\n${miss.join(" dan ")} belum mengisi closing di ROUNA OS.`;
  }

  if (kind === "midday") {
    if (out.length) L.push(`🔴 <b>Stok habis (${out.length})</b>: ${out.slice(0, 8).map((i) => esc(i.name)).join(", ")}`);
    if (waitApprove) L.push(`🟡 <b>${waitApprove} pengajuan order</b> menunggu persetujuan`);
    if (!L.length) return null;
    return `📦 <b>Perlu tindakan · ${fdate(t)}</b>\n` + L.join("\n");
  }

  // morning
  const [cashM, daily, cly, sopY, payables, moves] = await Promise.all([one("cash", y.slice(0, 7)), one("daily", y), one("closings", y), one("sop", y), col("payables"), one("moves", y)]);
  const cashY = Object.values(cashM?.rec || {}).filter((c: any) => c.date === y && !c.void) as Doc[];
  const salesY = cashY.length ? cashY.reduce((s, c) => s + (+c.total || (+c.cashPos || 0) + (+c.qrPos || 0) + (+c.card || 0)), 0) : (daily?.pl?.revenue || 0);
  const tgtMonth = +settings?.tgtMonth || 0;
  const dim = (m: string) => new Date(Date.UTC(+m.slice(0, 4), +m.slice(5), 0)).getUTCDate();
  const tgtDay = tgtMonth ? tgtMonth / dim(y.slice(0, 7)) : 0;
  if (salesY) L.push(`💰 <b>Penjualan kemarin</b>: ${rp(salesY)}${tgtDay ? ` (${pct(salesY / tgtDay)} dari target harian ${rp(tgtDay)})` : ""}${cashY.length ? "" : " · laporan Olsera"}`);
  else L.push(`💰 <b>Penjualan kemarin</b>: belum ada data kas atau laporan Olsera`);
  if (tgtMonth) {
    const cm = await one("cash", mo);
    const mtd = Object.values(cm?.rec || {}).filter((c: any) => !c.void && c.date < t).reduce((s: number, c: any) => s + (+c.total || (+c.cashPos || 0) + (+c.qrPos || 0) + (+c.card || 0)), 0);
    const day = +t.slice(8) - 1;
    if (day > 0) L.push(`🎯 <b>Bulan ini</b>: ${rp(mtd)} dari target ${rp(tgtMonth)} (${pct(mtd / tgtMonth)}; seharusnya ${pct(day / dim(mo))})`);
  }
  const missC = ["bar", "kitchen"].filter((a) => !cly?.shifts?.[a]).map((a) => a === "bar" ? "Bar" : "Kitchen");
  L.push(missC.length ? `⚠️ <b>Closing kemarin</b> belum lengkap: ${missC.join(", ")}` : `✅ <b>Closing kemarin</b> lengkap`);
  // waste yesterday: closing spoil + waste form
  const cost: Record<string, number> = Object.fromEntries(items.map((i) => [i.id, +i.cost || 0]));
  const name: Record<string, string> = Object.fromEntries(items.map((i) => [i.id, i.name]));
  const W: Record<string, number> = {};
  Object.values(cly?.shifts || {}).forEach((sh: any) => Object.entries(sh.lines || {}).forEach(([id, l]: [string, any]) => { if (l.spoil > 0) W[id] = (W[id] || 0) + l.spoil * (cost[id] || 0); }));
  Object.values(moves?.list || {}).forEach((e: any) => { if (e.t === "waste" && e.qty > 0) W[e.itemId] = (W[e.itemId] || 0) + e.qty * (cost[e.itemId] || 0); });
  const wTot = Object.values(W).reduce((s, v) => s + v, 0);
  if (wTot > 0) { const top = Object.entries(W).sort((a, b) => b[1] - a[1])[0]; L.push(`🗑️ <b>Waste kemarin</b>: ${rp(wTot)} · terbesar ${esc(name[top[0]] || "?")} ${rp(top[1])}`); }
  if (low.length) L.push(`📦 <b>Stok menipis (${low.length})</b>: ${low.slice(0, 6).map((i) => `${esc(i.name)}${(+st[i.id]?.gudang || 0) <= 0 ? " (habis)" : ""}`).join(", ")}${low.length > 6 ? ", …" : ""}`);
  if (waitApprove || waitRecv) L.push(`🧾 <b>Order</b>: ${waitApprove} menunggu persetujuan · ${waitRecv} menunggu barang`);
  const due = payables.filter((p) => { const paid = Object.values(p.paid || {}).reduce((s: number, x: any) => s + (+x.amt || 0), 0); return !p.void && paid < (+p.amt || 0) && p.due && p.due <= addDays(t, 3); });
  if (due.length) { const sum = due.reduce((s, p) => s + (+p.amt || 0) - Object.values(p.paid || {}).reduce((a: number, x: any) => a + (+x.amt || 0), 0), 0); L.push(`📅 <b>Utang jatuh tempo ≤3 hari</b>: ${due.length} invoice, ${rp(sum)}`); }
  const sopMiss = ["bar-open", "bar-close", "kitchen-open", "kitchen-close"].filter((k) => !sopY?.runs?.[k]);
  if (sopMiss.length) L.push(`📋 <b>SOP kemarin belum diisi</b>: ${sopMiss.length} dari 4 checklist`);
  return `☕ <b>Ringkasan pagi · ${fdate(t)}</b>\n${esc(settings?.outlet || "Coffee Rouna")}\n\n` + L.join("\n");
}

async function tg(token: string, method: string, body: unknown) {
  const r = await fetch(`https://api.telegram.org/bot${token}/${method}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });
  return await r.json();
}
function toWa(html: string) {
  return html.replace(/<\/?b>/g, "*").replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&");
}
async function waSend(token: string, target: string, text: string) {
  const fd = new FormData(); fd.append("target", target); fd.append("message", toWa(text));
  try { const r = await fetch("https://api.fonnte.com/send", { method: "POST", headers: { Authorization: token }, body: fd }); const j = await r.json(); return { ok: !!j.status, detail: j.reason || j.detail || "" }; }
  catch (e) { return { ok: false, detail: String(e) }; }
}
async function broadcast(text: string) {
  let n = 0;
  const cfg = await getSecret("tg"); const chats = (await getSecret("tg_chats")) || [];
  if (cfg?.token) for (const c of chats) { const r = await tg(cfg.token, "sendMessage", { chat_id: c.id, text, parse_mode: "HTML", disable_web_page_preview: true }); if (r.ok) n++; }
  const wa = await getSecret("wa");
  if (wa?.token) for (const t of wa.targets || []) { const r = await waSend(wa.token, t, text); if (r.ok) n++; }
  return n;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: Doc; try { body = await req.json(); } catch { return fail("Body tidak valid."); }
  const action = String(body.action || "");
  try {
    if (action === "cron") {
      if (!body.key || body.key !== await getSecret("cron_key")) return fail("forbidden", 403);
      const cfg = (await one("settings", "notify")) || {};
      const kind = String(body.kind || "morning");
      if (cfg[kind] === false) return json({ ok: true, skipped: "off" });
      const text = await compose(kind);
      return json({ ok: true, sent: text ? await broadcast(text) : 0 });
    }
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: who } = await admin.auth.getUser(token);
    if (!who?.user) return fail("Sesi habis. Masuk lagi.", 401);
    const { data: prof } = await admin.from("profiles").select("staff_id").eq("user_id", who.user.id).maybeSingle();
    const me = prof ? await one("staff", prof.staff_id) : null;
    if (!me || me.active === false || !["owner", "manager"].includes(me.role)) return fail("Hanya Owner atau Manager.", 403);

    const cfg = await getSecret("tg");
    if (action === "status") {
      const chats = (await getSecret("tg_chats")) || [];
      const wa = await getSecret("wa");
      return json({ bot: cfg?.bot || "", hasToken: !!cfg?.token, chats: chats.map((c: Doc) => ({ id: c.id, name: c.name })), wa: { hasToken: !!wa?.token, targets: wa?.targets || [] } });
    }
    if (action === "setToken") {
      const tk = String(body.token || "").trim();
      if (!/^\d+:[\w-]{30,}$/.test(tk)) return fail("Format token tidak dikenali. Salin persis dari BotFather.");
      const r = await tg(tk, "getMe", {});
      if (!r.ok) return fail("Token ditolak Telegram. Cek lagi.");
      await setSecret("tg", { token: tk, bot: r.result.username });
      return json({ ok: true, bot: r.result.username });
    }
    if (action === "waSet") {
      const prev = (await getSecret("wa")) || {};
      const token = String(body.token || "").trim() || prev.token;
      if (!token) return fail("Isi token Fonnte.");
      const targets = String(body.targets ?? (prev.targets || []).join(",")).split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean)
        .map((x) => /@g\.us$/.test(x) ? x : x.replace(/\D/g, "").replace(/^0/, "62")).filter((x) => x.length >= 9);
      await setSecret("wa", { token, targets });
      return json({ ok: true, targets });
    }
    if (action === "waTest") {
      const wa = await getSecret("wa"); if (!wa?.token || !(wa.targets || []).length) return fail("Isi token dan nomor penerima dulu.");
      const res = []; for (const t of wa.targets) res.push({ t, ...(await waSend(wa.token, t, "✅ <b>ROUNA OS</b> terhubung. Notifikasi Coffee Rouna akan dikirim ke sini.")) });
      const bad = res.filter((r) => !r.ok);
      return bad.length ? fail("Gagal ke " + bad.map((r) => r.t + (r.detail ? " (" + r.detail + ")" : "")).join(", ")) : json({ ok: true, sent: res.length });
    }
    if (action === "waOff") { await admin.from("secrets").delete().eq("key", "wa"); return json({ ok: true }); }
    if (action === "send") {
      const kind = String(body.kind || "morning");
      const text = await compose(kind) || (kind === "closing" ? "✅ Closing hari ini sudah lengkap." : "✅ Tidak ada yang perlu ditindaklanjuti saat ini.");
      return json({ ok: true, sent: await broadcast(text), text });
    }
    if (!cfg?.token) return fail("Hubungkan bot Telegram dulu.");
    if (action === "link") {
      const r = await tg(cfg.token, "getUpdates", { limit: 100, timeout: 0 });
      if (!r.ok) return fail("Gagal membaca pesan bot.");
      const chats: Doc[] = (await getSecret("tg_chats")) || [];
      const fresh: Doc[] = [];
      for (const u of r.result || []) {
        const m = u.message || u.my_chat_member; const c = m?.chat; if (!c) continue;
        if (u.message && !/^\/start/.test(u.message.text || "")) continue;
        if (chats.some((x) => x.id === c.id) || fresh.some((x) => x.id === c.id)) continue;
        fresh.push({ id: c.id, name: c.title || [c.first_name, c.last_name].filter(Boolean).join(" ") || c.username || String(c.id) });
      }
      if (fresh.length) {
        await setSecret("tg_chats", [...chats, ...fresh]);
        for (const c of fresh) await tg(cfg.token, "sendMessage", { chat_id: c.id, text: "✅ Terhubung ke ROUNA OS. Notifikasi Coffee Rouna akan dikirim ke sini." });
      }
      const last = (r.result || []).pop(); if (last) await tg(cfg.token, "getUpdates", { offset: last.update_id + 1, limit: 1, timeout: 0 });
      return json({ ok: true, added: fresh.map((c) => c.name) });
    }
    if (action === "unlink") {
      const chats: Doc[] = (await getSecret("tg_chats")) || [];
      await setSecret("tg_chats", chats.filter((c) => String(c.id) !== String(body.chatId)));
      return json({ ok: true });
    }
    return fail("Aksi tidak dikenal.");
  } catch (e) {
    console.error(e);
    return fail("Server error: " + (e instanceof Error ? e.message : String(e)), 500);
  }
});
