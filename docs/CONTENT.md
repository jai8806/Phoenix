# Content: précis to Ustaad

## Copyright first

The DGNCC précis carry this notice: *"This book or part thereof may not be
reproduced by any person or agency in any manner."* This repository is
public, so:

- **Never commit** précis PDFs or anything extracted from them. `content/sources/`
  and `content/build/` are git-ignored for this reason.
- What *is* committed: the pipeline code, tests on made-up text, and the
  table of contents (subject codes, names, periods and start pages) that the
  app shows in Learn.
- Extracted passages and questions go only to the private knowledge base
  (Supabase storage and the `documents` / `document_chunks` / `questions`
  tables, readable only by signed-in cadets of a unit).
- Before Phoenix is offered beyond a pilot unit, get written permission from
  DGNCC (through the Group HQ or Directorate) to use the précis this way.

## What has been ingested

| Document | Coverage | Result |
| --- | --- | --- |
| Special Subject (Army) JD/JW, 2025 edition, Part 1 of 2 | Master index (25 subjects); chapters AF I–IV, Indian Armed Forces (book pp. 1–50) | 56 passages, 45 draft MCQs (AF I–III; AF IV's questions are in Part 2) |

Still needed:

- Army JD/JW **Part 2**: Field Craft & Battle Craft, Military Communication,
  Map Reading, Weapons & Equipment (book pp. 51–280).
- Army **SD/SW** précis. JD/JW is the Junior Division, i.e. the A
  Certificate; B and C Certificate cadets follow the Senior Division précis.
- The **common subjects** précis, plus Navy, Air Force and RVC special subjects.

## Pipeline

```bash
pip install pdfplumber

# 1. Parse a précis into the index, passages and draft questions (content/build/<name>/)
python3 tools/ingest/ingest.py content/sources/army_jd_jw_2025_part1.pdf \
    --wing army --level junior --title "Special Subject (Army) JD/JW" --edition 2025

# 2. Try retrieval locally (keyword search, no AI call)
python3 tools/ingest/ask.py "Who is the Supreme Commander of the Armed Forces?"

# 3. Write a SQL load script to paste into the Supabase SQL Editor (content/build/<name>/load.sql)
python3 tools/ingest/to_sql.py content/build/army_jd_jw_2025_part1

# 4. Regenerate the app's subject list from the index
python3 tools/ingest/export_syllabus.py content/build/army_jd_jw_2025_part1/index.json \
    --name armyJunior --out app/lib/data/syllabus/army_junior.dart

# Tests (synthetic text only)
python3 -m pytest tools/ingest/tests
```

### How a précis is parsed

The précis use one fixed layout, which `tools/ingest/precis.py` relies on:

1. **Master index:** each row gives a code (`MR-IV`), a title, periods, a type
   (`T2` + `P1` = 2 theory and 1 practical) and the start page. The type
   tokens add up to the book's own totals, so they're used for period counts.
2. **Chapters** open with `CHAPTER AF I: …`. Titles come from the index,
   because headings can wrap.
3. **Passages:** the teaching-instructions block is skipped. Text is split at
   section headings (`INTRODUCTION`, `PART I: …`, `CONCLUSION`, `SUMMARY`) and
   at numbered paragraphs, into passages of about 1,400 characters. Each one
   keeps its chapter, section and printed page numbers, which become the
   citation (e.g. "Special Subject (Army) JD/JW · AF I · Introduction · p. 2").
4. **Assessment MCQs** are parsed into draft questions. **The précis prints no
   answer key**, so every question is stored as `draft` with no correct answer
   until an ANO sets and approves it in the Command Center. Short- and
   long-answer questions are not imported yet.

## Loading into Supabase

`to_sql.py` writes a `load.sql` per précis. It inserts a `documents` row for
the shared official syllabus, its passages into `document_chunks`, and the MCQs
into `questions` as drafts. Paste it into the SQL Editor; re-running it
replaces the earlier load. Shared material is readable only by signed-in
members of a unit (never anonymously), and drafts only by unit admins.
`search_chunks(question)` returns the best passages with their pages for
Ustaad.

## Next steps

1. Upload the PDFs to a private storage bucket so the ANO can open the source page.
2. Add embeddings (multilingual, 1024 dimensions) and blend vector search into
   `search_chunks`.
3. ANO review queue in the Command Center: pick the correct option, edit and
   approve draft questions.
4. Ustaad Edge Function: `search_chunks`, then Claude answers only from those
   passages and cites them.
