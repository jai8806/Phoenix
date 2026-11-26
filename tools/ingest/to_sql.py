"""Write a SQL script that loads an ingested précis into Supabase.

    python3 tools/ingest/to_sql.py content/build/army_jd_jw_2025_part1 content/build/army_jd_jw_2025_part2 \
        --out content/build/army_jd_jw_2025.sql

Pass every volume of one book together: they share a title, and the script
replaces that book's questions as a whole. Writes the --out file (keep it under
content/build/, which is git-ignored). Paste it into the
Supabase SQL Editor, which runs as the database owner, so no secret key ever
leaves your dashboard. Re-running it replaces the earlier load of the same
document. Questions go in as drafts in the shared bank, hidden from cadets
until an answer is set and they are approved.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

TAG = "$phx$"


def q(value) -> str:
    """Quote a value as a SQL literal using dollar quoting."""
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value)
    if TAG in text:
        raise ValueError(f"text contains the quoting tag {TAG}")
    return f"{TAG}{text}{TAG}"


def q_array(values: list[str]) -> str:
    return "array[" + ", ".join(q(v) for v in values) + "]::text[]"


def _title(doc: dict) -> str:
    return f"{doc['title']} ({doc['edition']})" if doc.get("edition") else doc["title"]


def build_parts(volumes: list[tuple[dict, list[dict], list[dict]]], max_bytes: int = 240_000) -> list[str]:
    """SQL for one book, split into parts that each stay under ``max_bytes``.

    The Supabase SQL Editor refuses very large queries, so a big book becomes
    several scripts, each its own transaction, run in order. Part 1 clears the
    earlier load and creates the document rows; later parts add passages to
    those rows by their storage path, then the questions.
    """
    doc0 = volumes[0][0]["document"]
    title = _title(doc0)
    wing = f"{q(doc0['wing'])}::wing" if doc0["wing"] != "common" else "null"
    sources = [v[0]["document"]["source_file"] for v in volumes]

    setup = ["-- Replace any earlier load of this book.",
             f"delete from questions where unit_id is null and subject = {q(title)} and status = 'draft';"]
    for src in sources:
        setup.append(f"delete from documents where unit_id is null and storage_path = {q('precis/' + src)};")
    for src in sources:
        setup.append("insert into documents (unit_id, title, subject, wing, division_level, storage_path) "
                     f"values (null, {q(title)}, null, {wing}, {q(doc0['level'])}, {q('precis/' + src)});")
    statements: list[str] = ["\n".join(setup)]

    def batches(rows: list[str], head: str, tail: str) -> None:
        budget = max_bytes - 4_000  # room for the part's header and footer
        current: list[str] = []
        size = 0
        for row in rows:
            if current and size + len(row.encode()) > budget - len((head + tail).encode()):
                statements.append(head + ",\n".join(current) + tail)
                current, size = [], 0
            current.append(row)
            size += len(row.encode()) + 2
        if current:
            statements.append(head + ",\n".join(current) + tail)

    for index, passages, _ in volumes:
        src = index["document"]["source_file"]
        rows = []
        for p in passages:
            pages = p["book_pages"] or [None]
            first, last = pages[0], pages[-1]
            heading = f"{p['chapter_code']} · {p['chapter_title']} · {p['section']}"
            rows.append(f"  ({q(first)}::smallint, {q(last if last != first else None)}::smallint, "
                        f"{q(heading)}, {q(p['text'])})")
        batches(
            rows,
            "insert into document_chunks (document_id, page, page_end, heading, content)\n"
            "select d.id, v.page, v.page_end, v.heading, v.content from documents d, (values\n",
            f"\n) as v(page, page_end, heading, content)\nwhere d.unit_id is null and d.storage_path = "
            f"{q('precis/' + src)};",
        )

    questions = [item for _, _, qs in volumes for item in qs]
    batches(
        [f"  (null, {q(title)}, {wing}, {q(item['prompt'])}, {q_array(item['options'])}, null, "
         f"{q(item['chapter_code'] + ' · Q' + str(item['number']))}, 'draft', {q(item['book_page'])})"
         for item in questions],
        "insert into questions (unit_id, subject, wing, prompt, options, correct_index, explanation, "
        "status, source_page) values\n",
        ";",
    )

    check = "\n".join([
        "-- Check: counts for this book (complete once every part has run).",
        f"select (select count(*) from documents where title = {q(title)}) as volumes,",
        f"       (select count(*) from document_chunks c join documents d on d.id = c.document_id "
        f"where d.title = {q(title)}) as passages,",
        f"       (select count(*) from questions where subject = {q(title)} and status = 'draft') as draft_questions;",
    ])

    # Pack statements into parts under the size limit.
    packed: list[list[str]] = [[]]
    for stmt in statements:
        if packed[-1] and sum(len(x.encode()) for x in packed[-1]) + len(stmt.encode()) > max_bytes - 2_000:
            packed.append([])
        packed[-1].append(stmt)
    n = len(packed)
    parts = []
    for i, group in enumerate(packed, 1):
        header = [f"-- Phoenix knowledge base load: {title}, from {', '.join(sources)}",
                  "-- Generated by tools/ingest/to_sql.py. Contains DGNCC précis text: do not commit or share."]
        if n > 1:
            header.append(f"-- Part {i} of {n}. Run the parts in order"
                          + (": this one first, it clears the earlier load." if i == 1 else "."))
        body = header + ["begin;", ""] + [g + "\n" for g in group] + ["commit;", ""]
        if i == n:
            body += [check, ""]
        parts.append("\n".join(body))
    return parts


def build_sql(volumes: list[tuple[dict, list[dict], list[dict]]]) -> str:
    """The whole book as one script (no size limit)."""
    return build_parts(volumes, max_bytes=10**12)[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("build_dirs", type=Path, nargs="+", help="one directory per volume of the same book")
    ap.add_argument("--out", type=Path, required=True,
                    help="output file; a big book is written as <stem>_part1of3.sql and so on")
    ap.add_argument("--max-kb", type=int, default=240, help="size limit per file for the SQL Editor")
    args = ap.parse_args()
    volumes = []
    for d in args.build_dirs:
        volumes.append((json.loads((d / "index.json").read_text()),
                        [json.loads(l) for l in (d / "passages.jsonl").open()],
                        [json.loads(l) for l in (d / "questions.jsonl").open()]))
    titles = {v[0]["document"]["title"] for v in volumes}
    if len(titles) != 1:
        raise SystemExit(f"All volumes must belong to one book; got titles {sorted(titles)}")
    parts = build_parts(volumes, args.max_kb * 1000)
    for old in args.out.parent.glob(f"{args.out.stem}_part*of*.sql"):
        old.unlink()
    if len(parts) == 1:
        args.out.write_text(parts[0])
        written = [args.out]
    else:
        args.out.unlink(missing_ok=True)
        written = []
        for i, part in enumerate(parts, 1):
            path = args.out.with_name(f"{args.out.stem}_part{i}of{len(parts)}.sql")
            path.write_text(part)
            written.append(path)
    print(f"{len(volumes)} volume(s), {sum(len(v[1]) for v in volumes)} passages, "
          f"{sum(len(v[2]) for v in volumes)} draft questions -> "
          + ", ".join(f"{w.name} ({w.stat().st_size // 1000} KB)" for w in written))


if __name__ == "__main__":
    main()
