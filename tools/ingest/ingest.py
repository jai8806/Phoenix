"""Turn a précis PDF into JSONL ready for the knowledge base.

    python3 tools/ingest/ingest.py content/sources/army_jd_jw_2025_part1.pdf \
        --wing army --level junior --title "Special Subject (Army) JD/JW" --edition 2025

Writes to content/build/<stem>/ (git-ignored):
    index.json       subjects from the master index
    passages.jsonl   one passage per line, with chapter, section and printed pages
    questions.jsonl  MCQs from the assessment exercises, as drafts without answers

Nothing here leaves the machine. Uploading to Supabase and embedding are
separate steps so the précis text never lands in this public repository.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

import pdfplumber

sys.path.insert(0, str(Path(__file__).parent))
from precis import (  # noqa: E402
    build_passages,
    fill_book_pages,
    parse_index_groups,
    parse_master_index,
    parse_mcqs,
    split_chapters,
    to_page,
)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf", type=Path)
    ap.add_argument("--wing", required=True, choices=["army", "navy", "air", "rvc", "common"])
    ap.add_argument("--level", required=True, choices=["junior", "senior"])
    ap.add_argument("--title", required=True, help="Document title shown in citations")
    ap.add_argument("--edition", default="")
    ap.add_argument("--out", type=Path, default=Path("content/build"))
    args = ap.parse_args()

    with pdfplumber.open(args.pdf) as pdf:
        pages = [to_page(i + 1, p.extract_text() or "") for i, p in enumerate(pdf.pages)]
    pages = fill_book_pages(pages)

    index_text = "\n".join(p.text for p in pages if "MASTER INDEX" in p.text or p.text.startswith("SER CODE"))
    index = parse_master_index(index_text)
    chapters = split_chapters(pages, index)

    doc = {"title": args.title, "wing": args.wing, "level": args.level, "edition": args.edition,
           "source_file": args.pdf.name}
    out = args.out / args.pdf.stem
    out.mkdir(parents=True, exist_ok=True)

    (out / "index.json").write_text(json.dumps(
        {"document": doc,
         "groups": parse_index_groups(index_text),
         "subjects": [{**asdict(e), "total_periods": e.total_periods} for e in index]},
        indent=2, ensure_ascii=False))

    n_passages = n_questions = 0
    with (out / "passages.jsonl").open("w") as fp, (out / "questions.jsonl").open("w") as fq:
        for ch in chapters:
            for p in build_passages(ch):
                fp.write(json.dumps({**doc, **asdict(p), "citation": f"{args.title} · {p.citation}"},
                                    ensure_ascii=False) + "\n")
                n_passages += 1
            for q in parse_mcqs(ch):
                fq.write(json.dumps({**doc, **asdict(q)}, ensure_ascii=False) + "\n")
                n_questions += 1

    print(f"{args.pdf.name}: {len(index)} subjects in index, {len(chapters)} chapters, "
          f"{n_passages} passages, {n_questions} draft MCQs -> {out}")
    for ch in chapters:
        print(f"  {ch.code}: {ch.title} (pdf pages {ch.pages[0].pdf_page}-{ch.pages[-1].pdf_page})")


if __name__ == "__main__":
    main()
