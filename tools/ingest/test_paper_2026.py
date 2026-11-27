import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from paper_2026 import questions, split_options  # noqa: E402


def test_inline_options_split_in_order():
    prompt, opts = split_options("How many obstacles are there?A) 8B) 10C) 12D) 15")
    assert prompt == "How many obstacles are there?"
    assert opts == [("A", "8"), ("B", "10"), ("C", "12"), ("D", "15")]


def test_letters_inside_words_are_not_markers():
    prompt, opts = split_options("A. Balancing abilityB. Physical strengthC. Jumping abilityD. Problem-solving")
    assert prompt == ""
    assert [t for _, t in opts] == ["Balancing ability", "Physical strength", "Jumping ability", "Problem-solving"]


def test_three_layouts_give_the_same_questions():
    plain = ["Q one?", "w", "x", "y", "z"]
    lettered = ["19. Q one?", "A) w", "B) x", "C) y", "D) z"]
    inline = ["Q one?", "A. wB. xC. yD. z"]
    for lines in (plain, lettered, inline):
        assert questions(lines) == [("Q one?", ["w", "x", "y", "z"])]


def test_stray_answer_letters_are_ignored():
    assert questions(["D", "D", "Q?", "a", "b", "c", "d"]) == [("Q?", ["a", "b", "c", "d"])]
