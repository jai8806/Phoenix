"""Parser tests on synthetic text that mimics the précis layout.

No précis text is used here: the book may not be reproduced, and this
repository is public.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ask import search  # noqa: E402
from precis import (  # noqa: E402
    Chapter,
    build_passages,
    fill_book_pages,
    parse_master_index,
    parse_mcqs,
    smart_title,
    split_chapters,
    to_page,
)

INDEX = """MASTER INDEX: SPECIAL SUBJECT (DEMO) (JD/JW)
SER CODE SUBJECT PERIODS TYPE PAGE
NO 1st 2nd
Yr Yr
(CODE- XY) DEMO FORCES (4 PERIODS)
1. XY-I INTRODUCTION TO DEMO 1 T 01
FORCES
2. XY-II FIELD WORK 1 2 T2 15
AND SIGNALS P1
3. XY-III SIGNALS DRILL T1 22
P1
4. XY-IV RADIO (GPS) PRACTICE 1 P 30
T3
TOTAL PERIODS 3 4
P3
"""


def test_master_index_rows_titles_and_periods():
    rows = parse_master_index(INDEX)
    assert [r.code for r in rows] == ["XY-I", "XY-II", "XY-III", "XY-IV"]
    assert rows[0].title == "Introduction to Demo Forces"
    assert (rows[0].theory_periods, rows[0].practical_periods) == (1, 0)
    # Wrapped title and a type token on the continuation line.
    assert rows[1].title == "Field Work and Signals"
    assert (rows[1].theory_periods, rows[1].practical_periods) == (2, 1)
    # No period numbers printed: counts come from the type tokens.
    assert (rows[2].theory_periods, rows[2].practical_periods) == (1, 1)
    # Bare "P" means all periods are practical; the stray totals token is ignored.
    assert rows[3].title == "Radio (GPS) Practice"
    assert (rows[3].theory_periods, rows[3].practical_periods) == (0, 1)
    assert rows[1].book_page == 15


def test_smart_title_keeps_acronyms_and_numerals():
    assert smart_title("PART II: THE INDIAN ARMY") == "Part II: The Indian Army"
    assert smart_title("TYPES OF COMMUNICATION: (LINE & RADIO)") == "Types of Communication: (Line & Radio)"
    assert smart_title("CENTRAL ARMED POLICE FORCES (CAPF) AND STATE POLICE") == \
        "Central Armed Police Forces (CAPF) and State Police"


def test_page_numbers_are_read_and_inferred():
    pages = fill_book_pages([
        to_page(10, "DEMO (JD/JW)\nCHAPTER XY I: INTRODUCTION TO DEMO"),
        to_page(11, "2\nINTRODUCTION\n1. First para."),
    ])
    assert pages[1].book_page == 2 and pages[1].text.startswith("INTRODUCTION")
    assert pages[0].book_page == 1  # opening page prints no number


def _chapter() -> Chapter:
    pages = fill_book_pages([
        to_page(10, "DEMO (JD/JW)\nCHAPTER XY I: INTRODUCTION TO DEMO\n“A quote.”\n"
                    "TEACHING INSTRUCTIONS\nPeriod : 01 (40 Mins)\nInstructor notes to skip."),
        to_page(11, "2\nINTRODUCTION\n1. Alpha forces guard the northern plains.\n"
                    "PART I: THE ALPHA FORCE\n2. The alpha force was raised in 1901.\n"
                    "3. Its headquarters is in Rivertown."),
        to_page(12, "3\nCONCLUSION\n4. Alpha matters.\nASSESSMENT EXERCISE\nMultiple Choice Questions\n"
                    "Q1. Where is the alpha headquarters?\n(a) Hilltown\n(b) Rivertown\n(c) Lakeside\n(d) Seaport\n"
                    "Q2. When was the alpha force\nraised?\n(a) 1901 (b) 1910\n(c) 1947 (d) 1950\n"
                    "Short Answers Type Questions\nQ1. Describe the alpha force."),
    ])
    return split_chapters(pages)[0]


def test_passages_skip_instructions_and_carry_sections_and_pages():
    ch = _chapter()
    assert ch.code == "XY I"
    passages = build_passages(ch)
    sections = [p.section for p in passages]
    assert sections == ["Introduction", "Part I: The Alpha Force", "Conclusion"]
    assert all("Instructor notes" not in p.text for p in passages)
    assert all("Q1." not in p.text for p in passages)  # assessment kept out of passages
    assert passages[1].book_pages == [2]
    assert passages[1].citation == "XY I · Part I: The Alpha Force · p. 2"


def test_mcqs_parse_wrapped_prompts_and_inline_options():
    qs = parse_mcqs(_chapter())
    assert [q.number for q in qs] == [1, 2]  # short-answer section is not parsed as MCQs
    assert qs[0].options == ["Hilltown", "Rivertown", "Lakeside", "Seaport"]
    assert qs[1].prompt == "When was the alpha force raised?"
    assert qs[1].options == ["1901", "1910", "1947", "1950"]
    assert all(q.correct_index is None and q.status == "draft" for q in qs)
    assert qs[0].book_page == 3


def test_search_finds_relevant_passage_and_refuses_unrelated():
    passages = [
        {"section": "Part I", "text": "The alpha force headquarters is in Rivertown.", "citation": "a"},
        {"section": "Part II", "text": "Beta squadrons fly from Hilltown airfield.", "citation": "b"},
    ]
    assert search(passages, "Where is the alpha headquarters?")[0][1]["citation"] == "a"
    assert search(passages, "chocolate cake recipe") == []


def test_index_groups():
    from precis import parse_index_groups
    assert parse_index_groups(INDEX) == {"XY": "Demo Forces"}


def test_to_sql_builds_an_idempotent_load():
    from to_sql import build_sql, q
    import pytest
    index = {"document": {"title": "Demo", "edition": "2025", "wing": "army", "level": "junior",
                          "source_file": "demo.pdf"}}
    passages = [{"chapter_code": "XY I", "chapter_title": "Intro", "section": "Introduction",
                 "book_pages": [2, 3], "text": "It's the alpha force."}]
    questions = [{"chapter_code": "XY I", "number": 1, "prompt": "Where?", "options": ["A", "B"],
                  "book_page": 3}]
    sql = build_sql([(index, passages, questions)])
    assert sql.startswith("-- Phoenix knowledge base load") and "begin;" in sql and "commit;" in sql
    assert "delete from documents" in sql  # re-running replaces the earlier load
    assert "$phx$It's the alpha force.$phx$" in sql  # apostrophes survive dollar quoting
    assert "'draft'" in sql and "array[$phx$A$phx$, $phx$B$phx$]::text[]" in sql
    with pytest.raises(ValueError):
        q("sneaky $phx$ text")


def test_volume_that_opens_mid_chapter_and_skips_index_pages():
    pages = fill_book_pages([
        to_page(1, "51\nASSESSMENT EXERCISE\nMultiple Choice Questions\nQ8. Pick one\n(a) Yes (b) No"),
        to_page(2, "CHAPTER WISE INDEX: DEMO (JD/JW)\nSER NO SUBJECT CODE AND CONTENT PAGE NO\n"
                   "CHAPTER XY II: SIGNALS\n1. Introduction 54"),
        to_page(3, "SER NO SUBJECT CODE AND CONTENT PAGE NO\nCHAPTER XY III: RADIO\n2. Summary 60"),
        to_page(4, "DEMO (SD/SW)\nCHAPTER XY II: SIGNALS\nINTRODUCTION\n1. Flags are used by day."),
    ])
    chapters = split_chapters(pages, continues="XY I")
    assert [c.code for c in chapters] == ["XY I", "XY II"]  # no fake chapters from index pages
    assert [q.number for q in parse_mcqs(chapters[0])] == [8]
    assert build_passages(chapters[1])[0].text == "1. Flags are used by day."  # (SD/SW) banner dropped


def test_option_parsing_handles_book_quirks():
    from precis import split_options
    # Missing closing bracket in the book.
    assert split_options("(a) 25 (b 150", "a") == [("a", "25"), ("b", "150")]
    # Answers that mention other options stay whole.
    assert split_options("(c) Both (a) and (b) (d) None", "c") == [("c", "Both (a) and (b)"), ("d", "None")]
    # A line that doesn't start with the expected marker is not an option line.
    assert split_options("covers (b) only", "a") == []


def test_mcq_stops_at_missing_question_marker_and_answer_sections():
    pages = fill_book_pages([
        to_page(10, "DEMO (JD/JW)\nCHAPTER XY I: DEMO"),
        to_page(11, "2\nINTRODUCTION\n1. Text.\nASSESSMENT EXERCISE\n"
                    "Multiple Choice Questions and Fill in the Blanks\n"
                    "Q1. Scale 1:50000 means\n(a) 1 cm = 0.5 km (b 1 cm = 5 km\n(c) Both (a) and (b) (d) None\n"
                    "Q2. Lost marker follows\n(a) One (b) Two\n(c) Three (d) Four\n"
                    "Next question with no Q marker\n(a) X (b) Y\n"
                    "Q3. ________ is a fill in the blank.\n"
                    "Q4. Last one\n(a) Yes\n(b) No\nShort Answer Type\nQuestions\nQ1. Explain."),
    ])
    qs = parse_mcqs(split_chapters(pages)[0])
    assert [q.number for q in qs] == [1, 2, 4]  # Q3 has no options
    assert qs[0].options == ["1 cm = 0.5 km", "1 cm = 5 km", "Both (a) and (b)", "None"]
    assert qs[1].options == ["One", "Two", "Three", "Four"]  # not merged with the unnumbered question
    assert qs[2].options == ["Yes", "No"]  # answer-section heading not glued on


def test_short_tail_merges_into_previous_passage():
    long_para = "1. " + "Alpha forces patrol the plains. " * 30
    pages = fill_book_pages([
        to_page(10, "DEMO (JD/JW)\nCHAPTER XY I: DEMO"),
        to_page(11, f"2\nINTRODUCTION\n{long_para}\nend of the sentence."),
    ])
    passages = build_passages(split_chapters(pages)[0], max_chars=400)
    assert all(len(p.text) >= 200 for p in passages)
    assert passages[-1].text.endswith("end of the sentence.")


def test_two_column_options_and_misprinted_letter():
    from precis import _fix_layouts
    assert _fix_layouts(["Photography (c) Choreography", "Cartography (d) None of these"]) == \
        ["Photography", "Cartography", "Choreography", "None of these"]
    assert _fix_layouts(["Topography", "Geography", "Polygraphy (c) Radiography"]) == \
        ["Topography", "Geography", "Polygraphy", "Radiography"]
    assert _fix_layouts(["1 km (c) 2 km", "3 km (b) (d) 50 km"]) == ["1 km", "3 km", "2 km", "50 km"]
    # Four ordinary options, one mentioning others, are left alone.
    opts = ["Yes", "No", "Both (a) and (b)", "Neither"]
    assert _fix_layouts(opts) == opts


def test_unnumbered_pages_count_on_from_the_last_number():
    pages = fill_book_pages([to_page(1, "10\nA"), to_page(2, "B"), to_page(3, "C"), to_page(4, "13\nD")])
    assert [p.book_page for p in pages] == [10, 11, 12, 13]
    assert smart_title("FIELD CRAFT /BATTLE CRAFT") == "Field Craft / Battle Craft"


SDSW = [
    "1\nUNIT 2 : DEMO WORK\nINDEX\nSer No Lesson Code Subject Page Number\n1. DW-1 Getting started 03 05\n"
    "2. DW-2 Going further 06 09",
    "2\nUNIT 2 : DEMO WORK\nKnowledge Understanding Application\nOutcome table to skip.",
    "3\nCHAPTER - I\nGETTING STARTED WITH\nDEMO WORK\nIntroduction\nDemo work begins with planning.\n"
    "Command Posts\nEach post has a commander and a signaller.",
    "4\nCHAPTER - I\nGOING FURTHER\nIntroduction\nAdvanced demo work needs practice.\n"
    "Comprehension Questions\nQ1. Answer the following:\n(a) What is demo work?",
]


def test_sdsw_units_chapters_sections_and_questions_skipped():
    from precis import build_passages_sdsw, split_sdsw
    pages = fill_book_pages([to_page(i + 1, t) for i, t in enumerate(SDSW)])
    units, chapters = split_sdsw(pages)
    assert [(u.prefix, u.name) for u in units] == [("DW", "Demo Work")]
    # Numbered by order: the book's misprinted second "CHAPTER - I" becomes DW-2.
    assert [(c.code, c.title) for c in chapters] == [("DW-1", "Getting Started with Demo Work"),
                                                       ("DW-2", "Going Further")]
    first = build_passages_sdsw(chapters[0])
    assert [p.section for p in first] == ["Introduction", "Command Posts"]
    assert first[1].citation == "DW-1 · Command Posts · p. 3"
    second = " ".join(p.text for p in build_passages_sdsw(chapters[1]))
    assert "Advanced demo work" in second and "What is demo work" not in second
    assert all("Outcome table" not in p.text for c in chapters for p in build_passages_sdsw(c))


def test_big_books_split_into_ordered_parts_under_the_limit():
    from to_sql import build_parts
    index = {"document": {"title": "Demo", "edition": "", "wing": "common", "level": "senior",
                          "source_file": "demo.pdf"}}
    passages = [{"chapter_code": "XY-1", "chapter_title": "Intro", "section": "Introduction",
                 "book_pages": [i], "text": "word " * 400} for i in range(1, 41)]
    parts = build_parts([(index, passages, [])], max_bytes=20_000)
    assert len(parts) > 1
    assert all(len(p.encode()) <= 20_000 for p in parts)
    assert "delete from documents" in parts[0] and all("delete from" not in p for p in parts[1:])
    assert all(p.count("begin;") == 1 and p.count("commit;") == 1 for p in parts)
    assert "Check: counts" in parts[-1]
    assert sum(p.count("word word") > 0 for p in parts) >= len(parts) - 1
    total_rows = sum(p.count("::smallint, null::smallint") for p in parts)
    assert total_rows == 40  # every passage lands in exactly one part
