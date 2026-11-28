"""Extract figures from a précis into small WebP files tagged by chapter and page.

    python3 tools/ingest/figures.py content/sources/army_sd_sw_2025.pdf \
        --passages content/build/army_sd_sw_2025/passages.jsonl --book army_sd_sw_2025

Writes content/build/figures/<book>/<id>.webp and figures.jsonl (git-ignored).
Each embedded image larger than a small icon is cropped from the rendered
page, so figures drawn over or around an image come out as they look in the
book. Logos and decorations repeated on many pages are dropped, as are
duplicates.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
from collections import Counter
from pathlib import Path

import pdfplumber
import pypdfium2 as pdfium

MIN_W, MIN_H = 90, 60  # points; smaller images are icons and bullets
MAX_WIDTH_PX = 900
DPI = 130


def page_to_chapter(passages_file: Path) -> dict[int, tuple[str, str]]:
    """Printed page -> (chapter code, chapter title), from the ingested passages."""
    mapping: dict[int, tuple[str, str]] = {}
    for line in passages_file.open():
        p = json.loads(line)
        for page in p["book_pages"]:
            mapping.setdefault(page, (p["chapter_code"], p["chapter_title"]))
    return mapping


def printed_page(text: str) -> int | None:
    first = (text or "").strip().splitlines()[:1]
    return int(first[0]) if first and first[0].strip().isdigit() else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("pdf", type=Path)
    ap.add_argument("--passages", type=Path, required=True)
    ap.add_argument("--book", required=True, help="folder name, e.g. army_sd_sw_2025")
    ap.add_argument("--out", type=Path, default=Path("content/build/figures"))
    args = ap.parse_args()

    chapters = page_to_chapter(args.passages)
    known_pages = sorted(chapters)
    out_dir = args.out / args.book
    out_dir.mkdir(parents=True, exist_ok=True)

    # First pass: find candidate images and how often each image repeats.
    candidates = []
    with pdfplumber.open(args.pdf) as pdf:
        last_printed = None
        for i, page in enumerate(pdf.pages):
            printed = printed_page(page.extract_text() or "")
            printed = printed if printed is not None else (last_printed + 1 if last_printed else None)
            last_printed = printed
            for img in page.images:
                w, h = img["x1"] - img["x0"], img["bottom"] - img["top"]
                if w < MIN_W or h < MIN_H:
                    continue
                key = (round(w), round(h), img.get("stream").get("Length") if img.get("stream") else None)
                candidates.append({"pdf_page": i, "printed": printed, "bbox": (img["x0"], img["top"], img["x1"], img["bottom"]),
                                   "key": key, "page_w": float(page.width), "page_h": float(page.height)})
    repeats = Counter(c["key"] for c in candidates)

    doc = pdfium.PdfDocument(str(args.pdf))
    seen_hashes: set[str] = set()
    records = []
    dropped = Counter()
    for c in candidates:
        if repeats[c["key"]] > 3:
            dropped["repeated logo or decoration"] += 1
            continue
        page_no = c["printed"]
        if page_no is None or not known_pages:
            dropped["no page number"] += 1
            continue
        # Nearest page that belongs to a chapter (figures can sit on pages with little text).
        nearest = min(known_pages, key=lambda p: abs(p - page_no))
        if abs(nearest - page_no) > 2:
            dropped["outside any chapter"] += 1
            continue
        code, title = chapters[nearest]
        scale = DPI / 72
        page_img = doc[c["pdf_page"]].render(scale=scale).to_pil()
        x0, top, x1, bottom = c["bbox"]
        pad = 4
        box = (max(0, int((x0 - pad) * scale)), max(0, int((top - pad) * scale)),
               min(page_img.width, int((x1 + pad) * scale)), min(page_img.height, int((bottom + pad) * scale)))
        crop = page_img.crop(box).convert("RGB")
        if crop.width > MAX_WIDTH_PX:
            crop = crop.resize((MAX_WIDTH_PX, int(crop.height * MAX_WIDTH_PX / crop.width)))
        digest = hashlib.sha1(crop.tobytes()).hexdigest()[:16]
        if digest in seen_hashes:
            dropped["duplicate"] += 1
            continue
        seen_hashes.add(digest)
        buf = io.BytesIO()
        crop.save(buf, "WEBP", quality=62, method=6)
        fig_id = f"{code.replace('/', '_')}-p{page_no}-{digest[:6]}"
        (out_dir / f"{fig_id}.webp").write_bytes(buf.getvalue())
        records.append({"id": fig_id, "book": args.book, "chapter_code": code, "chapter_title": title,
                        "page": page_no, "width": crop.width, "height": crop.height,
                        "path": f"{args.book}/{fig_id}.webp", "bytes": len(buf.getvalue())})

    with (out_dir / "figures.jsonl").open("w") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    total = sum(r["bytes"] for r in records)
    print(f"{args.pdf.name}: {len(records)} figures, {total / 1e6:.1f} MB -> {out_dir}; dropped {dict(dropped)}")


BOOK_TITLES = {
    "army_sd_sw_2025": "Special Subject (Army) SD/SW",
    "common_sd_sw_2025": "Common Subject SD/SW",
    # Must equal the document titles the load scripts write, so the app matches figures to the right book.
    "army_sdsw_oct2025": "Special Subject (Army) SD/SW (Oct 2025)",
    "tech_skills_sdsw_oct2025": "Tech Skills SD/SW (Oct 2025)",
    "nbcp_sdsw_oct2025": "NB & CP SD/SW (Oct 2025)",
    "life_skills_sdsw_oct2025": "Life Skills SD/SW (Oct 2025)",
}


def write_sql(out_root: Path, sql_path: Path, books: list[str] | None = None) -> None:
    """A SQL script that (re)loads the figure metadata of the given books (all books when none are named).

    Each book's earlier rows are replaced, so books can be loaded in separate scripts.
    """
    files = sorted(out_root.glob("*/figures.jsonl"))
    if books:
        files = [f for f in files if f.parent.name in books]
    rows = [json.loads(l) for f in files for l in f.open()]
    q = lambda v: "null" if v is None else (str(v) if isinstance(v, int) else "'" + str(v).replace("'", "''") + "'")
    lines = ["-- Phoenix précis figures metadata. Generated by tools/ingest/figures.py.", "begin;"]
    for f in files:
        lines.append(f"delete from figures where document_title = {q(BOOK_TITLES.get(f.parent.name, f.parent.name))};")
    for i in range(0, len(rows), 200):
        chunk = rows[i:i + 200]
        lines.append("insert into figures (id, document_title, chapter_code, page, storage_path, width, height) values")
        lines.append(",\n".join(
            f"  ({q(r['id'])}, {q(BOOK_TITLES.get(r['book'], r['book']))}, {q(r['chapter_code'])}, {q(r['page'])}, "
            f"{q(r['path'])}, {q(r['width'])}, {q(r['height'])})" for r in chunk) + ";")
    lines += ["commit;", "select document_title, count(*) as figures from figures group by 1 order by 1;", ""]
    sql_path.write_text("\n".join(lines))
    print(f"Wrote {sql_path}: {len(rows)} figures, {sql_path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    import sys as _sys
    if len(_sys.argv) > 1 and _sys.argv[1] == "sql":
        # python3 tools/ingest/figures.py sql [book ...] [--out path]
        a = _sys.argv[2:]
        out = Path(a[a.index("--out") + 1]) if "--out" in a else Path("content/build/figures.sql")
        names = [x for i, x in enumerate(a) if x != "--out" and (i == 0 or a[i - 1] != "--out")]
        write_sql(Path("content/build/figures"), out, names or None)
    else:
        main()
