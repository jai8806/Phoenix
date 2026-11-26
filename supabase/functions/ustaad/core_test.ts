import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1";
import {
  answerQuestion,
  buildUserPrompt,
  citedSources,
  ConfigError,
  ModelError,
  modelConfig,
  NOT_COVERED,
  type Passage,
} from "./core.ts";

const passages: Passage[] = [
  { chunk_id: 1, document_title: "Demo Précis", heading: "XY I · Intro", page: 2, page_end: null,
    content: "The alpha force headquarters is in Rivertown." },
  { chunk_id: 2, document_title: "Demo Précis", heading: "XY II · Signals", page: 5, page_end: 6,
    content: "Flags are used by day." },
];

const gemini = { provider: "gemini" as const, apiKey: "test-key", model: "gemini-3.5-flash-lite" };

function fakeFetch(reply: unknown, status = 200, seen: { url?: string; body?: any; headers?: any } = {}) {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    seen.url = String(url);
    seen.body = JSON.parse(String(init?.body));
    seen.headers = init?.headers;
    return new Response(JSON.stringify(reply), { status });
  }) as typeof fetch;
}

Deno.test("prompt numbers passages with their source and pages", () => {
  const p = buildUserPrompt("Where is the HQ?", passages);
  assertStringIncludes(p, "[1] (Demo Précis · XY I · Intro · p. 2)");
  assertStringIncludes(p, "[2] (Demo Précis · XY II · Signals · p. 5–6)");
  assert(p.endsWith("Cadet's question: Where is the HQ?"));
});

Deno.test("only cited passages become sources, in citation order", () => {
  const s = citedSources("Rivertown [1]. Also see [1] and [9].", passages);
  assertEquals(s, [{ n: 1, title: "Demo Précis", heading: "XY I · Intro", pages: "2" }]);
});

Deno.test("Gemini call sends key in header and system instruction, returns cited answer", async () => {
  const seen: any = {};
  const reply = { candidates: [{ content: { parts: [{ text: "It is in Rivertown [1]." }] } }] };
  const out = await answerQuestion("Where is the HQ?", passages, gemini, fakeFetch(reply, 200, seen));
  assertEquals(out.covered, true);
  assertEquals(out.answer, "It is in Rivertown [1].");
  assertEquals(out.sources.map((s) => s.n), [1]);
  assertStringIncludes(seen.url, "/models/gemini-3.5-flash-lite:generateContent");
  assert(!seen.url.includes("test-key"), "key must not be in the URL");
  assertEquals(seen.headers["x-goog-api-key"], "test-key");
  assertStringIncludes(seen.body.systemInstruction.parts[0].text, "Answer ONLY from the numbered");
});

Deno.test("model saying NOT_COVERED gives the friendly not-covered answer", async () => {
  const reply = { candidates: [{ content: { parts: [{ text: "NOT_COVERED" }] } }] };
  const out = await answerQuestion("Who won the cricket final?", passages, gemini, fakeFetch(reply));
  assertEquals(out, { answer: NOT_COVERED, sources: [], covered: false });
});

Deno.test("no passages means no model call at all", async () => {
  let called = false;
  const f = (async () => {
    called = true;
    return new Response("{}");
  }) as typeof fetch;
  const out = await answerQuestion("anything", [], gemini, f);
  assertEquals(out.covered, false);
  assertEquals(called, false);
});

Deno.test("rate limit from the model surfaces as ModelError 429", async () => {
  const err = await assertRejects(() => answerQuestion("q?", passages, gemini, fakeFetch({ error: "quota" }, 429)), ModelError);
  assertEquals((err as ModelError).status, 429);
});

Deno.test("Anthropic provider is selectable by config", async () => {
  const cfg = modelConfig((k) => ({ LLM_PROVIDER: "anthropic", ANTHROPIC_API_KEY: "k" } as Record<string, string>)[k]);
  assertEquals(cfg.provider, "anthropic");
  const seen: any = {};
  const out = await answerQuestion("q?", passages, cfg,
    fakeFetch({ content: [{ type: "text", text: "Flags by day [2]." }] }, 200, seen));
  assertEquals(out.sources.map((s) => s.n), [2]);
  assertEquals(seen.url, "https://api.anthropic.com/v1/messages");
});

Deno.test("missing key is a configuration error; Gemini is the default", () => {
  let threw = false;
  try {
    modelConfig(() => undefined);
  } catch (e) {
    threw = e instanceof ConfigError;
  }
  assert(threw);
  assertEquals(modelConfig((k) => (k === "GEMINI_API_KEY" ? "g" : undefined)).model, "gemini-3.5-flash-lite");
});
