# Who can do what

| | Cadet | JUO / CSM / CQMS | CSUO / SUO | ANO |
|---|---|---|---|---|
| Learn, Ustaad, diary, tests, roll-call replies | ✓ | ✓ | ✓ | |
| Command Center: notices, events, roll-call lists, review queue | | ✓ | ✓ | ✓ |
| Build and edit mock drafts | | ✓ | ✓ | ✓ |
| Publish mocks, delete tests | | | ✓ | ✓ |
| Roster: ranks, appointments, roles | | | ✓ | ✓ (also the only one who can touch the ANO's profile) |
| Read and answer anonymous queries | | only those the cadet opened to them | ✓ | ✗ never |

Appointments live in `profiles.appointment` (`csuo`, `suo`, `juo`, `csm`, `cqms`) and
are only allowed on senior cadets. `is_unit_command()` (ANO, CSUO, SUO) guards the roster
and publishing; `can_handle_query()` guards queries. Nobody can change their own role or
appointment. See `supabase/migrations/20261201000000_command_drafts_queries.sql` and its
check script `supabase/tests/command_drafts_queries_check.sql`.

## Mock drafts

An OMR mock is generated as a draft (`tests.is_draft`). Drafts are hidden from cadets by
row-level security, cannot be attempted (trigger), and only the ANO / CSUO / SUO can
publish one (trigger, which also records `published_by`). The draft screen lays the paper
out like the real one (header, papers, section headings such as `NCC GENERAL (03x2 = 06)`)
with the answer to every question, and can share a PDF with an answer key for checking.
Edits go through `set_test_questions()`; corrected questions are saved as unit questions,
the précis originals stay untouched.

Patterns (`app/lib/domain/omr/exam_pattern.dart`):

* **B Certificate**: Kar & Goa Dte 2026 papers (Sets 1 and 2). Paper II Weapon Training 15,
  Paper III Misc 105, Army Special Subject 55. 175 MCQs, 350 marks, 3 hours, 33% in each paper.
* **C Certificate**: 2024-25 paper (Army SD/SW). Paper II Weapon Training 5, Paper III Misc
  115, Paper IV Specialised Subject (Army) 55. 175 MCQs, 350 marks, 3 hours.

## Anonymous queries

* No column identifies the asker. The phone makes a random 24-character ticket code; only
  its SHA-256 is stored (`queries.token_hash`), and the asker reads replies with the code
  (`my_queries`). Signing out removes the codes from the phone.
* Times are rounded (hour for the query, minute for messages) so they can't be matched to
  who was using the app at that moment.
* `query_quota` counts queries per person per day (max 5) for spam control; it is never
  linked to a query, and no one can read it through the API.
* Limits, said plainly to cadets in the app: whoever runs the Supabase project could, with
  effort, correlate server request logs with query times. Inside the app, nobody (seniors,
  ANO) can see who asked.
