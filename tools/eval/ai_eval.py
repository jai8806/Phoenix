"""Asks Gemini each question with what the app would send, and checks the answers.

    dart run tool/eval_ustaad.dart ../content/build questions.json --export=/tmp/q.jsonl   (in app/)
    python3 tools/eval/ai_eval.py /tmp/q.jsonl [model]

Uses the server's own prompt (ANSWER_PROMPT in supabase/functions/ustaad/core.ts)
and Gemini's OpenAI-compatible endpoint. Quick-fact questions are answered by
the fact, as in the app. The key comes from the environment's network proxy.
"""
import json, re, sys, time, urllib.request
from pathlib import Path

core = Path(__file__).resolve().parents[2] / "supabase/functions/ustaad/core.ts"
PROMPT = re.search(r"export const ANSWER_PROMPT = `(.*?)`;", core.read_text(), re.S).group(1)


def user_prompt(q, passages, facts):
    blocks = []
    for i, p in enumerate(passages):
        pages = None if p["page"] is None else (f"{p['page']}–{p['page_end']}" if p["page_end"] and p["page_end"] != p["page"] else f"{p['page']}")
        where = " · ".join(x for x in [p["title"], p["heading"], f"p. {pages}" if pages else None] if x)
        blocks.append(f"[{i + 1}] ({where})\n{p['content']}")
    checked = ("Checked facts:\n" + "\n".join(f"* {f}" for f in facts) + "\n\n") if facts else ""
    return f"{checked}Précis passages:\n\n" + "\n\n".join(blocks) + f"\n\nCadet's question: {q}"


def ask(model, system, user):
    body = json.dumps({"model": model, "temperature": 0.2, "max_tokens": 700,
                       "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}).encode()
    for attempt in range(5):
        req = urllib.request.Request("https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", body,
                                     {"content-type": "application/json", "authorization": "Bearer proxy-injected"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)["choices"][0]["message"]["content"].strip()
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                time.sleep(10 * (attempt + 1))
                continue
            raise
    return "ERROR: rate limited"


def main():
    rows = [json.loads(l) for l in open(sys.argv[1])]
    model = sys.argv[2] if len(sys.argv) > 2 else "gemini-3.5-flash-lite"
    ok = 0
    for r in rows:
        if r.get("fact"):
            answer = r["fact"]
        else:
            answer = ask(model, PROMPT, user_prompt(r["q"], r["passages"], []))
            time.sleep(2)
        text = answer.lower()
        has = lambda alt: any(a in text for a in alt.split("|"))
        good = any(map(has, r["any"])) if "any" in r else all(map(has, r["all"]))
        ok += good
        print(f"{'PASS' if good else 'FAIL'}  {r['q']}\n      {answer[:400].replace(chr(10), ' / ')}\n")
    print(f"{ok} / {len(rows)} correct with {model}")


main()
