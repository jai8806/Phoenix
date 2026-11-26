// Ustaad Edge Function: retrieves précis passages the signed-in cadet may read
// (row-level security applies, because the cadet's own token is used), then
// asks the configured model to answer from them with citations.
//
// Secrets (Dashboard -> Edge Functions -> Secrets):
//   GEMINI_API_KEY   free key from Google AI Studio (default provider)
//   LLM_MODEL        optional, defaults to gemini-3.5-flash-lite
//   LLM_PROVIDER     optional: "gemini" (default) or "anthropic" (+ ANTHROPIC_API_KEY)
//   USTAAD_DAILY_LIMIT  optional questions per cadet per day (default 50)

import { createClient } from "npm:@supabase/supabase-js@2";
import { answerQuestion, ConfigError, ModelError, modelConfig, type Passage } from "./core.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "content-type": "application/json" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "Sign in to ask Ustaad." }, 401);

  let question = "";
  try {
    question = String((await req.json()).question ?? "").trim();
  } catch {
    return json({ error: "Send a JSON body with a question." }, 400);
  }
  if (question.length < 3) return json({ error: "Ask a full question." }, 400);
  if (question.length > 500) return json({ error: "Keep questions under 500 characters." }, 400);

  const key = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? "";
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, key, { global: { headers: { Authorization: auth } } });

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return json({ error: "Your session has expired. Sign in again." }, 401);
  const userId = userData.user.id;

  const limit = Number(Deno.env.get("USTAAD_DAILY_LIMIT") ?? "50");
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count } = await supabase.from("ustaad_log").select("id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", since);
  if ((count ?? 0) >= limit) {
    return json({ error: `You've asked ${limit} questions today. Ustaad will be back tomorrow.` }, 429);
  }

  const { data: passages, error: searchError } = await supabase.rpc("search_chunks", { q: question, match_count: 6 });
  if (searchError) return json({ error: "Couldn't search the study material right now. Try again shortly." }, 502);

  try {
    const cfg = modelConfig((k) => Deno.env.get(k));
    const result = await answerQuestion(question, (passages ?? []) as Passage[], cfg);
    await supabase.from("ustaad_log").insert({ user_id: userId, question, answered: result.covered });
    return json(result);
  } catch (e) {
    if (e instanceof ConfigError) {
      console.error(e.message);
      return json({ error: "Ustaad isn't set up yet. Ask your ANO to add the AI key." }, 503);
    }
    if (e instanceof ModelError && (e.status === 429 || e.status === 503)) {
      return json({ error: "Ustaad is busy right now. Try again in a minute." }, 429);
    }
    console.error(e);
    return json({ error: "Ustaad couldn't answer just now. Try again in a moment." }, 502);
  }
});
