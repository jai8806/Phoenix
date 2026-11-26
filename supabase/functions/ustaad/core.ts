// Ustaad's core: prompt building and model calls, kept free of Supabase so it
// can be tested on its own. The model provider is swappable: Gemini (free
// tier) by default, or Anthropic Claude.

export interface Passage {
  chunk_id: number;
  document_title: string;
  heading: string | null;
  page: number | null;
  page_end: number | null;
  content: string;
}

export interface Source {
  n: number;
  title: string;
  heading: string | null;
  pages: string | null;
}

export interface Answer {
  answer: string;
  sources: Source[];
  covered: boolean;
}

export const NOT_COVERED =
  "I couldn't find this in your unit's study material. Ask your ANO, or try asking with words from the précis.";

export const SYSTEM_PROMPT = `You are Ustaad, a study assistant for NCC (National Cadet Corps) cadets in India.
Answer ONLY from the numbered précis passages provided. Rules:
- Use only facts stated in the passages. Never add outside knowledge, even if you know it.
- Cite the passages you used with their numbers in square brackets, e.g. [1] or [2][3].
- If the passages do not contain the answer, reply exactly: NOT_COVERED
- Be concise and clear for a student: a direct answer first, then short points if helpful.
- Reply in the same language as the question (English or Hindi).
- Do not give unsafe weapon-handling instructions beyond what the passages state, and remind cadets that live firing is only under a qualified instructor if weapons come up.`;

export function pagesLabel(p: Pick<Passage, "page" | "page_end">): string | null {
  if (p.page == null) return null;
  return p.page_end && p.page_end !== p.page ? `${p.page}–${p.page_end}` : `${p.page}`;
}

export function buildUserPrompt(question: string, passages: Passage[]): string {
  const blocks = passages.map((p, i) => {
    const pages = pagesLabel(p);
    const where = [p.document_title, p.heading, pages ? `p. ${pages}` : null].filter(Boolean).join(" · ");
    return `[${i + 1}] (${where})\n${p.content}`;
  });
  return `Précis passages:\n\n${blocks.join("\n\n")}\n\nCadet's question: ${question}`;
}

/** Keeps only the sources the answer actually cites, in citation order. */
export function citedSources(answer: string, passages: Passage[]): Source[] {
  const seen = new Set<number>();
  for (const m of answer.matchAll(/\[(\d{1,2})\]/g)) {
    const n = Number(m[1]);
    if (n >= 1 && n <= passages.length) seen.add(n);
  }
  return [...seen].map((n) => {
    const p = passages[n - 1];
    return { n, title: p.document_title, heading: p.heading, pages: pagesLabel(p) };
  });
}

export type Provider = "gemini" | "anthropic";

export interface ModelConfig {
  provider: Provider;
  apiKey: string;
  model: string;
}

export function modelConfig(env: (k: string) => string | undefined): ModelConfig {
  const provider = (env("LLM_PROVIDER") ?? "gemini").toLowerCase() as Provider;
  if (provider === "anthropic") {
    const apiKey = env("ANTHROPIC_API_KEY");
    if (!apiKey) throw new ConfigError("ANTHROPIC_API_KEY is not set");
    return { provider, apiKey, model: env("LLM_MODEL") ?? "claude-haiku-5-5" };
  }
  const apiKey = env("GEMINI_API_KEY");
  if (!apiKey) throw new ConfigError("GEMINI_API_KEY is not set");
  return { provider: "gemini", apiKey, model: env("LLM_MODEL") ?? "gemini-3.5-flash-lite" };
}

export class ConfigError extends Error {}
export class ModelError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

type Fetch = typeof fetch;

/** Calls the configured model and returns its text reply. */
export async function callModel(cfg: ModelConfig, system: string, user: string, fetcher: Fetch = fetch): Promise<string> {
  if (cfg.provider === "anthropic") {
    const res = await fetcher("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": cfg.apiKey, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({ model: cfg.model, max_tokens: 800, system, messages: [{ role: "user", content: user }] }),
    });
    if (!res.ok) throw new ModelError(`Anthropic ${res.status}: ${await res.text()}`, res.status);
    const data = await res.json();
    return (data.content ?? []).filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text).join("").trim();
  }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(cfg.model)}:generateContent`;
  const res = await fetcher(url, {
    method: "POST",
    headers: { "x-goog-api-key": cfg.apiKey, "content-type": "application/json" },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts: [{ text: user }] }],
      generationConfig: { temperature: 0.2, maxOutputTokens: 800 },
    }),
  });
  if (!res.ok) throw new ModelError(`Gemini ${res.status}: ${await res.text()}`, res.status);
  const data = await res.json();
  const parts = data.candidates?.[0]?.content?.parts ?? [];
  return parts.map((p: { text?: string }) => p.text ?? "").join("").trim();
}

/** Full answer flow once passages have been retrieved. */
export async function answerQuestion(
  question: string,
  passages: Passage[],
  cfg: ModelConfig,
  fetcher: Fetch = fetch,
): Promise<Answer> {
  if (passages.length === 0) return { answer: NOT_COVERED, sources: [], covered: false };
  const text = await callModel(cfg, SYSTEM_PROMPT, buildUserPrompt(question, passages), fetcher);
  if (!text || text.includes("NOT_COVERED")) return { answer: NOT_COVERED, sources: [], covered: false };
  return { answer: text, sources: citedSources(text, passages), covered: true };
}
