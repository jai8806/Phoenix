"""Question-bank parser tests on made-up questions in the formats seen in NCC banks."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from mcq_bank import parse_bank, split_options  # noqa: E402

BANK = [
    "ARMED FORCES\n"
    "1. The head of the demo army is __ _\n"
    "(a) Chief (b) Deputy (c) Captain (d) Cadet\n"
    "2. Which of these is NOT a demo award.\n"
    "(a) Gold Star (b) Silver Star\n(c) Paper Star (d) Bronze Star\n"
    "3. The role of ____ is to provide covering fire so the\n"
    "enemy does not interfere.\n"
    "A) Engineers B) Artillery C) Signals D) Medics\n",
    "Weapon Training\n"
    "Q4. How many loops does the demo pull-through have\n"
    "a) 1 b) 3 c) 2 d) 4\n"
    "Q.5. The demo bolt must be fully closed or the rifle will\n"
    "(a) Fire '(b) Misfire (c) Jam (d) Both (a) and (b)\n"
    "Answer: b) Misfire\n"
    "o6. A demo question from a scanned paper about distance\n"
    "(a) 10 m (b) 100 m (c) 1 km (d) None of these\n"
    "7. A garbled line with no options at all\n"
    "8. (c) 15 inch\n",
]


def test_parses_numbering_option_styles_and_sections():
    qs = parse_bank(BANK)
    assert [q.number for q in qs] == [1, 2, 3, 4, 5, 6]
    assert qs[0].section == "Armed Forces" and qs[3].section == "Weapon Training"
    assert qs[1].options == ["Gold Star", "Silver Star", "Paper Star", "Bronze Star"]
    assert qs[2].prompt == "The role of ____ is to provide covering fire so the enemy does not interfere."
    assert qs[2].options == ["Engineers", "Artillery", "Signals", "Medics"]
    assert qs[3].options == ["1", "3", "2", "4"]
    assert qs[4].options[3] == "Both (a) and (b)"  # stays whole
    assert qs[4].options[1] == "Misfire"  # stray quote dropped
    assert qs[4].correct_index == 1  # "Answer:" line used when present
    assert qs[5].prompt.startswith("A demo question from a scanned paper")  # "o6." scan noise
    assert all(q.status == "draft" for q in qs)
    assert all(q.correct_index is None for q in qs if q.number != 5)


def test_garbled_and_option_only_lines_are_dropped():
    numbers = [q.number for q in parse_bank(BANK)]
    assert 7 not in numbers and 8 not in numbers


def test_duplicates_in_a_bank_are_kept_once():
    qs = parse_bank(["DRILL\n1. Demo drill question here\n(a) A (b) B\n2. Demo drill question here?\n(a) A (b) B\n"])
    assert len(qs) == 1


def test_wrapped_option_text_is_not_a_section_heading():
    qs = parse_bank(["DRILL\n1. A long demo question about marching\n(a) Left foot (b) Right foot (c) Both\n"
                     "feet together (d) None\n2. Next demo question about turning\n(a) A (b) B\n"])
    assert {q.section for q in qs} == {"Drill"}
    assert qs[0].options[2] == "Both feet together"


def test_split_options_requires_order():
    assert split_options("(c) Both (a) and (b) (d) None", "c") == ["Both (a) and (b)", "None"]
    assert split_options("covers (b) only", "a") == []
