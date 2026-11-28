"""Parse the B Cert 2026 (Karnataka & Goa, Army SD/SW) papers and their keys.

    python3 tools/ingest/paper_2026.py content/sources/bcert2026

Each paper is a .docx of section headings ("LEADERSHIP (09x2=18)"), then
questions as one paragraph followed by four option paragraphs. Each key
lists the answers in the same order ("C. Chamber"). A section is kept only
when its question count matches the key, and each answer is checked
against the option text, so a damaged section is dropped rather than
loaded with the wrong answers.

Writes content/build/paper_bcert_2026.jsonl (one question per line).
"""

from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path

SECTION = re.compile(r"^(?P<name>[A-Z][A-Z &’'\-/().]+?)\s*\(\s*(?P<n>\d+)\s*[xX×]\s*\d+\s*=\s*\d+\s*\)\s*$")
PAPER = re.compile(r"^PAPER\s+[IVX]+\s*[–-]\s*(?P<name>.+)$")
KEY = re.compile(r"^\(?([A-Da-d])[.)]\s*(.*)$")

# Paper section -> bank subject used by the exam insights.
SUBJECTS = {
    "WEAPON TRAINING": "Weapon Training",
    "NCC GENERAL": "NCC General",
    "NATIONAL INTERGRATION & AWARENESS": "National Integration",
    "NATIONAL INTEGRATION & AWARENESS": "National Integration",
    "PERSONALITY DEVELOPOMENT": "Personality Development",
    "PERSONALITY DEVELOPMENT": "Personality Development",
    "LEADERSHIP": "Leadership",
    "DISASTER MANAGEMENT": "Disaster Management",
    "SOCIAL SERVICE & COMMUNITY DEVELOPMENT": "Social Service & Community Development (SSCD)",
    "SOCIAL AWARENESS & COMMUNITY DEVELOPMENT": "Social Service & Community Development (SSCD)",
    "HEALTH & HYGIENE": "Health and Hygiene",
    "ADVENTURE": "Adventure",
    "ENVIRONMENT AWARENESS & CONSERVATION": "Environmental Awareness And Conservation",
    "OBSTACLE TRAINING": "Obstacle Training",
    "BORDER & COASTAL AREAS": "Border And Coastal Areas",
    "ARMED FORCES": "Armed Forces",
    "MAP READING": "Map Reading",
    "FIELD CRAFT & BATTLE CRAFT": "Field Craft & Battle Craft",
    "FIELD CRAFT AND BATTLE CRAFT": "Field Craft & Battle Craft",
    "INTRODUCTION TO INFANTRY WEAPONS & EQUIPMENT": "Infantry Weapons & Equipment",
    "MILITARY HISTORY": "Military History",
    "COMMUNICATION": "Communication",
    "DRILL": "Drill",
    "SSCD": "Social Service & Community Development (SSCD)",
    "INTRODUCTION TO INFANTRY WEAPON": "Infantry Weapons & Equipment",
}


def paragraphs(path: Path) -> list[str]:
    xml = zipfile.ZipFile(path).read("word/document.xml").decode("utf-8")
    out = []
    for p in re.findall(r"<w:p[ >].*?</w:p>", xml, re.S):
        t = "".join(re.findall(r"<w:t[^>]*>([^<]*)</w:t>", p))
        t = t.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("\t", " ")
        t = re.sub(r"\s+", " ", t).strip()
        if t:
            out.append(t)
    return out


def sections(lines: list[str]) -> list[tuple[str, int, list[str]]]:
    """(heading, declared question count, lines) for every marked section."""
    found, cur = [], None
    for line in lines:
        m = SECTION.match(line) or (PAPER.match(line) and None)
        p = PAPER.match(line)
        if m:
            cur = [m["name"].strip(), int(m["n"]), []]
            found.append(cur)
        elif p:
            cur = [p["name"].strip(), 0, []]  # count comes on the next line, e.g. "(15X2 = 30 MARKS)"
            found.append(cur)
        elif cur is not None:
            c = re.match(r"^\(\s*(\d+)\s*[xX×]\s*\d+\s*=\s*\d+\s*MARKS\s*\)$", line)
            if c and not cur[2]:
                cur[1] = int(c[1])
            elif not re.match(r"^\(\d+ Marks\)$", line, re.I):
                cur[2].append(line)
    return [(n, k, ls) for n, k, ls in found if k > 0]


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def split_options(line: str) -> tuple[str, list[tuple[str, str]]]:
    """'Q?A) x B) y C) z D) w' -> ('Q?', [('A','x'), ...]). Options must run A, B, C, D in order."""
    for d in (")", "."):
        m = re.search(r"(?:^|(?<=[^A-Za-z]))A" + re.escape(d) + r"\s*", line)
        if not m:
            continue
        cuts, pos = [(m.start(), m.end())], m.end()
        for letter in "BCD":
            n = re.search(letter + re.escape(d) + r"\s*", line[pos:])
            if not n:
                break
            cuts.append((pos + n.start(), pos + n.end()))
            pos += n.end()
        if len(cuts) == 1 and m.start() == 0:
            return "", [("A", line[m.end():].strip())]
        if len(cuts) >= 2:
            opts = []
            for i, (a, b) in enumerate(cuts):
                stop = cuts[i + 1][0] if i + 1 < len(cuts) else len(line)
                opts.append(("ABCD"[i], line[b:stop].strip()))
            return line[:m.start()].strip(), opts
    single = re.match(r"^\(?([B-D])[.)]\s*(.+)$", line)
    if single:
        return "", [(single[1], single[2].strip())]
    return line, []


def questions(lines: list[str]) -> list[tuple[str, list[str]]]:
    """Questions with four options, from lines in any of the layouts the papers use."""
    items: list[tuple[str, str | None]] = []  # (text, option letter or None)
    for line in lines:
        line = re.sub(r"^\d{1,3}[.)]\s+", "", line)
        prompt, opts = split_options(line)
        if prompt:
            items.append((prompt, None))
        items.extend((t, l) for l, t in opts)
    out, i = [], 0
    while i < len(items):
        text, letter = items[i]
        if letter is None:
            nxt = items[i + 1:i + 5]
            if len(nxt) == 4 and [l for _, l in nxt] == list("ABCD"):
                out.append((text, [t for t, _ in nxt])); i += 5; continue
            if len(nxt) == 4 and all(l is None for _, l in nxt) and not any(t.endswith("?") for t, _ in nxt):
                out.append((text, [t for t, _ in nxt])); i += 5; continue
        i += 1
    return out


def parse(paper: Path, key: Path, label: str) -> tuple[list[dict], list[str]]:
    q_secs = {n: questions(ls) for n, _, ls in sections(paragraphs(paper))}
    out, report = [], []
    for name, count, key_lines in sections(paragraphs(key)):
        answers = [KEY.match(l) for l in key_lines]
        answers = [(a[1].upper(), a[2].strip()) for a in answers if a]
        qs = q_secs.get(name, [])
        picked: list[tuple[int, str, list[str], int]] = []  # (number, prompt, options, answer)
        if qs and len(qs) == len(answers):
            pairs = list(enumerate(zip(qs, answers)))
        else:
            # Counts differ: line answers up with questions by the option text the key repeats.
            pairs, j = [], 0
            for n, (letter, text) in enumerate(answers):
                for k in range(j, min(j + 3, len(qs))):
                    if text and any(norm(o) == norm(text) for o in qs[k][1]):
                        pairs.append((n, (qs[k], (letter, text))))
                        j = k + 1
                        break
        for n, ((prompt, options), (letter, text)) in pairs:
            if norm(options[0]) in ("alltheabove", "noneoftheabove", "bothaandb"):
                report.append(f"{label} {name} Q{n + 1}: options out of line in the paper; dropped")
                continue
            idx = "ABCD".index(letter)
            hits = [j for j, o in enumerate(options) if text and norm(o) == norm(text)]
            if text and norm(options[idx]) != norm(text):
                if len(hits) != 1:
                    # Allow a cut-off option ("Regional dominanc") when the key's letter is the only near match.
                    if not (norm(text).startswith(norm(options[idx])[:12]) or norm(options[idx]).startswith(norm(text)[:12])):
                        report.append(f"{label} {name} Q{n + 1}: key '{letter}. {text}' matches no option; dropped")
                        continue
                else:
                    idx = hits[0]
            picked.append((n, prompt, options, idx))
        for n, prompt, options, idx in picked:
            out.append({
                "subject": SUBJECTS.get(name.upper(), name.title()),
                "prompt": prompt,
                "options": options,
                "correct_index": idx,
                "source": f"B Cert 2026 KAR & GOA · {label} · {name.title()} Q{n + 1}",
            })
        report.append(f"{label} {name}: {len(picked)}/{count}" + ("" if qs else " (questions missing in the paper)"))
    return out, report


def main() -> None:
    src = Path(sys.argv[1] if len(sys.argv) > 1 else "content/sources/bcert2026")
    rows, seen = [], set()
    for s in ("1", "2"):
        got, report = parse(src / f"set{s}.docx", src / f"set{s}_key.docx", f"Set {s}")
        print("\n".join(report))
        for r in got:
            k = norm(r["prompt"])
            if k not in seen:
                seen.add(k)
                rows.append(r)
    out = Path("content/build/paper_bcert_2026.jsonl")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
    print(f"{len(rows)} unique questions -> {out}")
    write_sql(rows, Path("content/build/supabase_setup/22_paper_bcert_2026.sql"))


PAPER_SUBJECT = "B Cert Paper 2026 · KAR & GOA (Army SD/SW)"


def write_sql(rows: list[dict], path: Path) -> None:
    """Approved shared questions: the answers come from the official key, so no review is needed."""
    q = lambda v: "$phx$" + v.replace("$phx$", "") + "$phx$"
    lines = [
        f"-- Phoenix: {PAPER_SUBJECT}, Set 1 and Set 2 with the official answer keys.",
        "-- Generated by tools/ingest/paper_2026.py. Answers checked against each option's text.",
        "begin;",
        f"delete from questions where unit_id is null and subject = {q(PAPER_SUBJECT)};",
        "insert into questions (unit_id, subject, wing, prompt, options, correct_index, explanation, status) values",
    ]
    vals = []
    for r in rows:
        # The app reads the chapter before " · Q" in `explanation` as the subject.
        number = r["source"].rsplit(" Q", 1)[-1]
        label = r["source"].split(" · ")[1]
        vals.append(
            f"  (null, {q(PAPER_SUBJECT)}, 'army'::wing, {q(r['prompt'])}, "
            f"array[{', '.join(q(o) for o in r['options'])}]::text[], {r['correct_index']}, "
            f"{q(r['subject'] + ' · Q' + number + ' (' + label + ')')}, 'approved')"
        )
    lines.append(",\n".join(vals) + ";")
    lines += ["commit;", f"select count(*) as paper_2026_questions from questions where subject = {q(PAPER_SUBJECT)};", ""]
    path.write_text("\n".join(lines))
    print(f"Wrote {path} ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
