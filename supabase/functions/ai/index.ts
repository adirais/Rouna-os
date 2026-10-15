// ROUNA OS — AI analysis proxy (keeps the Anthropic API key on the server)
import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const MODEL = Deno.env.get("AI_MODEL") || "claude-sonnet-5-5";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ code: "not_configured", error: "Fitur AI belum diaktifkan (ANTHROPIC_API_KEY belum diisi)." }, 503);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") || "" } },
    auth: { persistSession: false },
  });
  const { data: role } = await sb.rpc("my_role");
  if (!["owner", "manager", "finance"].includes(String(role))) return json({ code: "not_granted", error: "Tidak diizinkan." }, 403);
  let prompt = "";
  try { prompt = String((await req.json()).prompt || "").slice(0, 60000); } catch { /* empty */ }
  if (!prompt) return json({ error: "Prompt kosong." }, 400);
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({ model: MODEL, max_tokens: 2000, messages: [{ role: "user", content: prompt }] }),
  });
  if (r.status === 429) return json({ code: "rate_limited", error: "Terlalu banyak permintaan." }, 429);
  const out = await r.json();
  if (!r.ok) return json({ code: "upstream", error: out?.error?.message || "Gagal." }, 502);
  const text = (out.content || []).filter((c: { type: string }) => c.type === "text").map((c: { text: string }) => c.text).join("\n");
  return json({ text });
});
