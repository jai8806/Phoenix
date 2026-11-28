# Phoenix product plan

## Why Phoenix

Existing NCC tools are built for one cadet studying alone:

| Product | Strength | Gap |
| --- | --- | --- |
| DGNCC Training app (official) | Syllabus, precis, videos, Hindi and English | One-way content, weak video player, nothing for units |
| NCC Journey (nccjourney.in) | Guides, camp calendar, mock tests, ebooks | A content site; no accounts, no unit features, no AI |
| NCC by Think Extra | Offline, 5,000+ bilingual MCQs, 350-mark mocks, 3D simulators | Solo study only; nothing for ANOs |
| Cadexa, Tejas NCC, Mission Cadet | Notes, MCQs, exam pattern pages | Passive, exam-only |

**Nobody serves the unit.** Phoenix's wedge is the institution layer: an ANO or
senior cadet hosting tests, a shared calendar, attendance that feeds a live
eligibility tracker, readiness analytics, and an assistant grounded in the
unit's own approved material. The heavier simulation ideas from the Cadet One
report come later, on top of that base.

## Users and roles

| Role | Can do |
| --- | --- |
| Cadet | Study, practise, take unit tests, keep a private training diary, ask Ustaad |
| Senior Cadet (SUO/JUO) | Everything a cadet can, plus host tests, post announcements, manage the calendar |
| ANO | Runs the unit: roles, records, attendance, knowledge base, sees diary entries cadets choose to share |

## Modules

**Cadet app:** Today (exam countdown, eligibility, daily Fall-In quiz, next
events, announcements) · Learn (syllabus by wing and division, practice, unit
tests, full mocks) · Ustaad (cited answers from the knowledge base) · Training
Diary · Me (service record, theme, sign-out).

**Command Center:** Overview (KPIs, cadets needing attention, upcoming events)
· Cadets (roster, attendance, eligibility) · Tests (builder, results, weak-topic
heatmap) · Calendar · Announcements · Knowledge base (uploads that feed Ustaad).

### Training Diary and AI briefs

After every session a cadet logs, in under a minute:

- Type: drill, shooting, PT, map reading, obstacle, cultural, other
- Shooting: rifle, position, distance, rounds, score, group size, target photo (later), conditions
- What went well, what to improve, instructor corrections
- Mood, fatigue, sleep
- Voice notes transcribed in Hindi or English (Phase 2)

Phoenix then:

1. **Tracks trends:** group size over time, weakest position, repeated corrections.
2. **Finds patterns:** e.g. scores dropping after short sleep. Worded as things
   to try, never diagnoses.
3. **Writes briefs** before IDSSC, RDC selection, TSC or SSB: form summary,
   strengths and weak spots with evidence, a 7-day focus plan, a
   competition-day checklist, and interview talking points drawn from the
   cadet's own entries. Every claim links to the entries it came from.

The diary is private by default. A cadet can share individual entries with the
ANO, who then gets a squad view (for example, picking an IDSSC team from six
weeks of real data). Target photos logged now become training data for the
shot-group analyser later.

## Exam facts the app relies on

Kept as data with a visible source, re-checked each season:

- **B Certificate written (2026-27):** 175 MCQs × 2 marks = 350 marks, 150
  minutes, negative marking; 240 marks common subjects, 110 marks wing
  subjects. Source: SNCCO 2026 as reported by Cadexa. Confirm against the
  official SNCCO before launch.
- **Eligibility:** 75% attendance of the training periods plus an Annual
  Training Camp; C Certificate also needs the B Certificate.

## Roadmap

| Phase | Scope |
| --- | --- |
| **0. Foundation** (this PR) | Flutter app, design system, roles, all screens on sample data, eligibility and marking logic, diary, Supabase schema with RLS |
| **1. MVP** | Supabase-backed data, offline cache (Drift), CSV roster import, QR parade attendance, knowledge-base ingestion and Ustaad v1 with citations, question bank editor, basic diary sync. Pilot in one unit |
| **2. Institution** | AI question drafts with ANO approval, results analytics and weak-topic heatmap, AI diary insights and briefs, ANO squad view, Hindi, push notifications, camps hub, Career Compass v1 |
| **3. Deep tech** | Drill pose feedback, 3D weapon lab, target photo analyser, Virtual Camp |

## Ustaad (RAG) design

1. Ingest PDFs: extract text, OCR scanned Hindi precis.
2. Split by heading into passages tagged with wing, level, subject and page.
3. Embed with a multilingual model (bge-m3 or Voyage multilingual, 1024 dims).
4. Retrieve with hybrid search: Postgres full-text plus pgvector.
5. Answer with Claude (Sonnet for chat, Haiku for cheap jobs like drafting
   questions), only from retrieved passages, citing document and page. If the
   material doesn't cover it, say so.
6. Evaluate against a set of 100 questions with known answers from the precis.
   Cadets can flag answers; admins review them.

## Content sources

- The eight official syllabus and precis folders (Army, Navy, Air Force, RVC;
  junior and senior).
- DGNCC (indiancc.nic.in): pages and circulars, ingested by a scraper run from
  a server.
- NCC Journey and other third-party sites are design inspiration only; their
  content is copyrighted and is not copied.

## Risks

| Risk | Mitigation |
| --- | --- |
| Minors' data (JD/JW cadets) | DPDP Act: guardian consent for under-18s (`guardian_consent_at`), minimal data, India-region hosting |
| AI answers that are wrong | Retrieval-only answers with citations, refusal when uncovered, flag-and-review loop, eval set |
| Out-of-date exam rules | Rules stored as data with a source and "as of" date |
| Implied official endorsement | No NCC crest or DGNCC branding until approval is granted |
| Scope creep | Ship the institution layer first; simulations later |
