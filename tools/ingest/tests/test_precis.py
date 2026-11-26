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
