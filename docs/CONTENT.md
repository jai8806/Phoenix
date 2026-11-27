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

| Book | Layout | Coverage | Result |
| --- | --- | --- | --- |
| Special Subject (Army) JD/JW, 2025, Parts 1 and 2 | `jdjw` | Master index (25 subjects) and all 25 chapters | 297 passages, 232 draft MCQs |
| Special Subject (Army) SD/SW | `sdsw` | 6 units, 40 chapters | 319 passages |
| Common Subject SD/SW | `sdsw` | 11 units, 103 chapters | 959 passages |

| MCQ Bank · Special Subject (Army) | `mcq_bank.py` | 6 subjects | 682 draft MCQs |
| MCQ Bank · Common Subject | `mcq_bank.py` | 14 subjects | 904 draft MCQs |
| B Cert Paper 2024 · KAR & GOA (Army SD/SW) | `mcq_bank.py --kind paper` | 95 of 175 questions readable in the scan | 95 draft MCQs |
| First Aid Lecture (H-5) | `--layout slides` | 147 slides | 59 passages |

| Practice Paper · General (C Cert pattern), Word | `mcq_bank.py` (.docx) | 4 labelled sections, rest marked Mixed | 223 draft MCQs |
| C Cert paper 2024-25 (scanned, bilingual) | OCR (Tesseract) | Marks per section only; questions too garbled to import | — |
| B Cert answer sheet 2025-26 (KAR & GOA) | — | Confirms structure and −0.5 negative marking | — |

**1,634 passages and 2,136 draft MCQs in all.** None of the question banks
include answer keys, so every question waits in the ANO's review queue.
Suggesting answers by matching options against the précis was tried and was
right only about half the time on a hand-checked sample, so no answer is
guessed. The SD/SW books are an older
edition (statistics up to about 2017) with no MCQs, only written
comprehension questions, and no period counts. The JD/JW book is the 2025
edition.

Not imported: fill-in-the-blank, short- and long-answer questions, and figures
(maps, signs, diagrams); only text is extracted.

Still needed:

- The **JD/JW common subjects** précis.
- **Navy, Air Force and RVC** special subjects (JD/JW and SD/SW).
- The current (2025) **SD/SW** editions, if the ones ingested are older.

## Pipeline

```bash
pip install pdfplumber

# 1. Parse each volume into the index, passages and draft questions (content/build/<name>/).
#    A later volume borrows the first one's index and can open mid-chapter.
python3 tools/ingest/ingest.py content/sources/army_jd_jw_2025_part1.pdf \
    --wing army --level junior --title "Special Subject (Army) JD/JW" --edition 2025
python3 tools/ingest/ingest.py content/sources/army_jd_jw_2025_part2.pdf \
    --wing army --level junior --title "Special Subject (Army) JD/JW" --edition 2025 \
    --index-from content/build/army_jd_jw_2025_part1/index.json --continues "AF IV"

# 2. Try retrieval locally (keyword search, no AI call)
python3 tools/ingest/ask.py "Who is the Supreme Commander of the Armed Forces?"

#    SD/SW books use the unit layout (no master index, no MCQs):
python3 tools/ingest/ingest.py content/sources/army_sd_sw_2025.pdf --layout sdsw \
    --wing army --level senior --title "Special Subject (Army) SD/SW"
python3 tools/ingest/ingest.py content/sources/common_sd_sw_2025.pdf --layout sdsw \
    --wing common --level senior --title "Common Subject SD/SW"

# 3. One SQL load script per book (all volumes together), for the Supabase SQL Editor
python3 tools/ingest/to_sql.py content/build/army_jd_jw_2025_part1 content/build/army_jd_jw_2025_part2 \
    --out content/build/army_jd_jw_2025.sql

# 4. Regenerate the app's subject list from the index
python3 tools/ingest/export_syllabus.py content/build/army_jd_jw_2025_part1/index.json \
    --name armyJunior --out app/lib/data/syllabus/army_junior.dart

# Question banks and past papers (no answer keys: questions arrive as drafts)
python3 tools/ingest/mcq_bank.py content/sources/qb_common.pdf --title "MCQ Bank · Common Subject" \
    --wing common --level senior
python3 tools/ingest/to_sql.py content/build/qb_common --out content/build/qb_common.sql

# Tests (synthetic text only)
python3 -m pytest tools/ingest/tests
```

### How a précis is parsed

Two layouts are supported. **SD/SW (`--layout sdsw`):** each unit opens
with "UNIT 2 : MAP READING" and a lesson index (codes like MR-3); chapters
open with "CHAPTER - III" (chapters are numbered by order in the unit, as the
book sometimes misprints the numeral); short Title Case lines are section
headings; unit-end comprehension questions are skipped. Pages without a
printed number take one counted on from the last numbered page.

**JD/JW 2025 (`--layout jdjw`, the default)** uses this layout:

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
4. **Assessment MCQs** are parsed into draft questions. Option markers are
   read strictly in order (a, b, c, d), so an answer like "Both (a) and (b)"
   stays whole. The parser also copes with the book's quirks: a missing
   bracket ("(b 150"), two-column options ("(a) … (c) …" over "(b) … (d) …"),
   a misprinted letter, and a question whose "Qn." marker is missing (that
   question is dropped rather than merged into the one before). **The précis prints no
   answer key**, so every question is stored as `draft` with no correct answer
   until an ANO sets and approves it in the Command Center. Short- and
   long-answer questions are not imported yet.

## Loading into Supabase

`to_sql.py` writes one load script per book. The Supabase SQL Editor rejects
queries over a size limit ("Query is too large"), so a big book is split into
parts of at most 240 KB (`--max-kb`), named `<book>_part1of5.sql` and so on.
Each part is its own transaction; run them in order. Part 1 clears the
earlier load, so re-running a whole book is safe. It inserts a `documents` row for
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

## Exam weightage and most-asked chapters

`tools/ingest/analyze_pyq.py` writes `app/lib/data/exam/cert_insights.dart`:

- **Marks per subject** from the 2024 B Cert paper (KAR & GOA, Army SD/SW),
  checked against its question numbering (2 marks each): Common 240, Special
  110. Leadership (18) is inferred from question numbers because its heading
  is unreadable in the scan. Drill has no written marks (practical only).
- **Most-asked chapters**: each bank and paper question is matched to the
  précis chapter it is about (keyword search within its subject); a chapter's
  share is the fraction of that subject's questions it got. 1,603 of 1,681
  questions matched. These are frequencies in the banks, a guide rather than
  a guarantee.

C Cert marks come from the 2024-25 C Cert paper, read with OCR; two
headings were unreadable and were identified from question numbers and
topics (Health & Hygiene 28, Obstacle Training 14). Its negative marking is
not printed, so −0.5 is assumed and labelled as such in the app.

Only numbers and chapter titles go into the app.

## Figures

`tools/ingest/figures.py` crops every embedded image larger than an icon from
the rendered page (130 dpi, WebP, at most 900 px wide), tags it with the
chapter and printed page, and drops logos repeated on many pages and
duplicates. Army SD/SW: 256 figures; Common SD/SW: 615 (about 10 MB in all).
They go to a private Supabase Storage bucket; the app shows them in the
chapter reader and under Ustaad's answers for the pages it quotes, using
short-lived signed links.
