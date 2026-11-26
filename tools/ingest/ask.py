"""Try Ustaad's retrieval step locally: keyword (BM25) search over ingested passages.

    python3 tools/ingest/ask.py "Who is the supreme commander of the armed forces?"

This is the keyword half of the hybrid search the app will run in Postgres
(full-text + pgvector). It shows which passages, with citations, an answer
would be built from. No LLM is called.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections import Counter
from pathlib import Path

STOP = set("a an and are as at be by for from has have in is it of on or that the to was were what which who with how why when where does do did".split())


def tokens(text: str) -> list[str]:
    return [t for t in re.findall(r"[a-z0-9]+", text.lower()) if t not in STOP and len(t) > 1]


class BM25:
    def __init__(self, docs: list[str], k1: float = 1.5, b: float = 0.75):
        self.docs = [tokens(d) for d in docs]
        self.k1, self.b = k1, b
        self.avg = sum(map(len, self.docs)) / max(len(self.docs), 1)
        df = Counter(t for d in self.docs for t in set(d))
        n = len(self.docs)
        self.idf = {t: math.log(1 + (n - f + 0.5) / (f + 0.5)) for t, f in df.items()}
        self.tf = [Counter(d) for d in self.docs]

    def scores(self, query: str) -> list[float]:
        q = tokens(query)
        out = []
        for d, tf in zip(self.docs, self.tf):
            s = 0.0
            for t in q:
                if t in tf:
                    f = tf[t]
                    s += self.idf[t] * f * (self.k1 + 1) / (f + self.k1 * (1 - self.b + self.b * len(d) / self.avg))
            out.append(s)
        return out


def search(passages: list[dict], query: str, k: int = 3) -> list[tuple[float, dict]]:
    bm = BM25([f"{p['section']} {p['text']}" for p in passages])
    ranked = sorted(zip(bm.scores(query), passages), key=lambda x: -x[0])
    return [(s, p) for s, p in ranked[:k] if s > 0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("question")
    ap.add_argument("--build", type=Path, default=Path("content/build"))
    ap.add_argument("-k", type=int, default=3)
    args = ap.parse_args()

    passages = [json.loads(l) for f in sorted(args.build.glob("*/passages.jsonl")) for l in f.open()]
    if not passages:
        raise SystemExit("No passages found. Run tools/ingest/ingest.py first.")
    hits = search(passages, args.question, args.k)
    if not hits:
        print("Nothing in the material covers this. Ustaad would say so rather than guess.")
    for score, p in hits:
        print(f"[{score:.1f}] {p['citation']}\n    {p['text'][:280]}…\n")


if __name__ == "__main__":
    main()
