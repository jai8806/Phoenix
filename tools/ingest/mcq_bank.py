"""Parse MCQ question banks and past papers into draft questions.

    python3 tools/ingest/mcq_bank.py content/sources/qb_common.pdf --title "MCQ Bank · Common Subject" \
        --wing common --level senior

Handles the layouts seen in NCC question banks and scanned papers:
  * numbering "1." / "Q1." / "Q.169." / "o168." (scan noise)
  * options "(a)" / "a)" / "A)" with optional stray quote, inline or one per line
  * section headings ("Weapon Training", "MAP READING (MR)") that name the subject
  * occasional "Answer: c) ..." lines, used as the answer when present
Questions without at least two clean options, or with a garbled prompt, are
dropped rather than imported wrong.

Writes content/build/<stem>/questions.jsonl (git-ignored). Answers are set
by the ANO in the review screen: keyword matching against the précis was
tried and picked the right option only about half the time, so no answer is
guessed here.
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, dataclass, field
from pathlib import Path

_Q = re.compile(r"^(?:Q\s*\.?\s*|o\s*)?(?P<n>\d{1,3})\s*[.)]\s*(?P<text>\S.*)$")
_MARK = re.compile(r"(?:(?<=\s)|^)['‘’]?\(?(?P<l>[a-dA-D])\)\s*")
_ANSWER = re.compile(r"^Answer\s*[:\-]\s*\(?(?P<l>[a-dA-D])\)", re.I)
_HEADING = re.compile(r"^[A-Za-z][A-Za-z &/()'’.-]{2,60}$")
LETTERS = "abcd"


@dataclass
class BankQuestion:
    section: str
    number: int
    prompt: str
    options: list[str]
    page: int
    correct_index: int | None = None
    status: str = "draft"
    extra: dict = field(default_factory=dict)


def split_options(line: str, expected: str) -> list[str]:
    """Options on a line, taking markers strictly in order from ``expected``."""
    found: list[tuple[int, int]] = []
    pos, want = 0, expected
    while want:
        m = next((c for c in _MARK.finditer(line, pos) if c.group("l").lower() == want), None)
        if m is None or (not found and line[: m.start()].strip(" '‘’")):
            break
        found.append((m.start(), m.end()))
        pos = m.end()
        want = LETTERS[LETTERS.index(want) + 1] if want != "d" else ""
    return [line[s:(found[i + 1][0] if i + 1 < len(found) else len(line))].strip() for i, (_, s) in enumerate(found)]


# Subject names as they appear in title case; ALL-CAPS headings are accepted as they are.
KNOWN_SECTIONS = {
    "ncc general", "ncc gen", "national integration", "national integration and awareness", "drill",
    "weapon training", "personality development", "leadership", "disaster management", "health and hygiene",
    "health & hygiene", "adventure", "adventure activities", "environmental awareness and conservation",
    "obstacle training", "border and coastal areas", "armed forces", "map reading", "field craft and battle craft",
    "military history", "communication", "communications", "introduction to infantry weapons and equipment",
    "social service & community development", "social service and community development", "first aid",
    "ncc integration and awareness", "national integration & awareness",
}


DOCX_COUNTS: dict[str, int] = {}


def docx_pages(path: Path) -> list[str]:
    """A Word paper as one page of text: headings kept, questions numbered
    (Word papers often leave them unnumbered), option paragraphs split into lines."""
    import docx

    lines: list[str] = []
    n = 0
    for para in docx.Document(str(path)).paragraphs:
        text = para.text.strip()
        if not text:
            continue
        m = re.search(r"\(\s*(\d+)\s*Questions?\s*\)\s*$", text, flags=re.I)
        head = re.sub(r"\s*(MCQs?)?\s*\(\s*\d+\s*Questions?\s*\)\s*$", "", text, flags=re.I)
        if m:
            lines.append(head.strip())
            DOCX_COUNTS[_clean_section(head.strip())] = int(m.group(1))
        elif split_options(text.splitlines()[0], "a"):
            lines.extend(l.strip() for l in text.splitlines() if l.strip())
        elif _Q.match(text):
            lines.append(text)
        else:
            n += 1
            lines.append(f"{n}. {text}")
    return ["\n".join(lines)]


def _is_heading(line: str, next_line: str | None) -> bool:
    if not _HEADING.match(line) or len(line.split()) > 8 or line.endswith("?"):
        return False
    if split_options(line, "a") or re.search(r"\b[a-dA-D]\)", line):
        return False
    letters = re.sub(r"[^A-Za-z]", "", line)
    known = re.sub(r"\s*\(.*?\)\s*", " ", line).strip().lower() in KNOWN_SECTIONS
    caps = len(letters) >= 4 and letters.isupper()
    return (known or caps) and next_line is not None and bool(_Q.match(next_line))


_FIX = {"Heal H And Hygiene": "Health and Hygiene", "Introt O Wpn & Eqpt": "Infantry Weapons & Equipment",
        "Ncc Gen": "NCC General", "Pmjay": "PMJAY", "Sscd": "SSCD", "Health& Hygiene": "Health and Hygiene"}


def _clean_section(s: str) -> str:
    s = re.sub(r"\s+", " ", s).strip(" -")
    s = s.title() if s.isupper() else s
    s = re.sub(r"\((\w+)\)", lambda m: f"({m.group(1).upper()})", s)  # (Mr) -> (MR)
    return _FIX.get(s, s)


def parse_bank(pages: list[str]) -> list[BankQuestion]:
    lines: list[tuple[int, str]] = [(i + 1, l.strip()) for i, t in enumerate(pages) for l in t.splitlines() if l.strip()]
    out: list[BankQuestion] = []
    section = "General"
    cur: dict | None = None

    def finish() -> None:
        if not cur:
            return
        opts = [re.sub(r"\s+", " ", o).strip(" '‘’") for o in cur["options"] if o.strip(" '‘’")]
        prompt = re.sub(r"\s+", " ", cur["prompt"]).strip()
        words = re.findall(r"[A-Za-z]{2,}", prompt)
        if len(opts) >= 2 and len(words) >= 3 and not prompt.startswith("("):
            out.append(BankQuestion(section, cur["n"], prompt, opts[:4], cur["page"], cur.get("answer")))

    for i, (page, line) in enumerate(lines):
        nxt = lines[i + 1][1] if i + 1 < len(lines) else None
        if _is_heading(line, nxt):
            finish()
            cur = None
            section = _clean_section(line)
            continue
        a = _ANSWER.match(line)
        if a and cur:
            idx = LETTERS.index(a.group("l").lower())
            if idx < len(cur["options"]):
                cur["answer"] = idx
            continue
        q = _Q.match(line)
        if q and not split_options(line, "a"):
            finish()
            cur = {"n": int(q.group("n")), "prompt": q.group("text"), "options": [], "page": page}
            continue
        if cur is None:
            continue
        expected = LETTERS[len(cur["options"])] if len(cur["options"]) < 4 else ""
        opts = split_options(line, expected) if expected else []
        if opts:
            cur["options"].extend(opts)
        elif cur["options"]:
            if len(cur["options"]) >= 4:
                continue
            # A wrapped option can share its line with the next one: "feet together (d) None".
            m = next((c for c in _MARK.finditer(line) if expected and c.group("l").lower() == expected), None)
            if m is not None and m.start() > 0:
                cur["options"][-1] += " " + line[: m.start()].strip()
                cur["options"].extend(split_options(line[m.start():].lstrip(), expected))
            else:
                cur["options"][-1] += " " + line  # wrapped option
        else:
            cur["prompt"] += " " + line  # wrapped prompt
    finish()

    # The same question sometimes appears twice in a bank; keep the first.
    seen: set[str] = set()
    unique = []
    for q in out:
        key = re.sub(r"[^a-z0-9]", "", q.prompt.lower())
        if key not in seen:
            seen.add(key)
            unique.append(q)
    return unique


def main() -> None:
    import pdfplumber

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf", type=Path)
    ap.add_argument("--title", required=True)
    ap.add_argument("--wing", required=True, choices=["army", "navy", "air", "rvc", "common"])
    ap.add_argument("--level", required=True, choices=["junior", "senior"])
    ap.add_argument("--kind", default="bank", choices=["bank", "paper"])
    ap.add_argument("--out", type=Path, default=Path("content/build"))
    args = ap.parse_args()

    if args.pdf.suffix.lower() == ".docx":
        pages = docx_pages(args.pdf)
    else:
        with pdfplumber.open(args.pdf) as pdf:
            pages = [p.extract_text() or "" for p in pdf.pages]
    questions = parse_bank(pages)
    # Word papers state how many questions each heading has; questions past
    # that count belong to later, unlabelled sections.
    seen_in: dict[str, int] = {}
    for q in questions:
        limit = DOCX_COUNTS.get(q.section)
        seen_in[q.section] = seen_in.get(q.section, 0) + 1
        if limit is not None and seen_in[q.section] > limit:
            q.section = "Mixed Subjects"

    doc = {"title": args.title, "wing": args.wing, "level": args.level, "edition": "", "source_file": args.pdf.name,
           "kind": args.kind}
    out = args.out / args.pdf.stem
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.json").write_text(json.dumps({"document": doc, "groups": {}, "subjects": []}, indent=2))
    (out / "passages.jsonl").write_text("")
    with (out / "questions.jsonl").open("w") as f:
        for q in questions:
            d = asdict(q)
            d.pop("extra")
            f.write(json.dumps({**doc, "chapter_code": q.section, "book_page": q.page, **d}, ensure_ascii=False) + "\n")

    from collections import Counter
    secs = Counter(q.section for q in questions)
    keyed = sum(q.correct_index is not None for q in questions)
    print(f"{args.pdf.name}: {len(questions)} questions in {len(secs)} sections; "
          f"{keyed} with an answer in the file -> {out}")
    for s, n in secs.items():
        print(f"  {s}: {n}")


if __name__ == "__main__":
    main()
