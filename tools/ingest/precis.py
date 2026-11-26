"""Parse an NCC précis PDF into passages and draft questions for Ustaad.

The précis follows a fixed layout that this parser relies on:

* a MASTER INDEX listing each chapter as ``<ser>. <CODE>-<ROMAN> <TITLE> <periods> <type> <page>``
* chapter openings like ``CHAPTER AF I: INTRODUCTION TO INDIAN ARMED FORCES``
* numbered paragraphs (``1.``, ``2.`` ...) grouped under ``PART I: ...`` headings
* an ``ASSESSMENT EXERCISE`` per chapter with MCQs ``Q1.`` + options ``(a)``–``(d)``
  followed by short and long answer questions
* the printed book page number on the first line of each content page

Pure functions over page text, so they can be tested without the PDF.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

ROMAN = r"(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3})"


@dataclass
class IndexEntry:
    code: str  # e.g. "AF-I"
    title: str
    theory_periods: int
    practical_periods: int
    book_page: int

    @property
    def total_periods(self) -> int:
        return self.theory_periods + self.practical_periods


@dataclass
class Page:
    pdf_page: int  # 1-based page in the PDF
    book_page: int | None  # printed page number, if any
    text: str


@dataclass
class Passage:
    chapter_code: str  # "AF I"
    chapter_title: str
    section: str  # "PART I: THE INDIAN ARMY", "INTRODUCTION", ...
    book_pages: list[int]
    text: str

    @property
    def citation(self) -> str:
        pages = sorted(set(self.book_pages))
        span = str(pages[0]) if len(pages) == 1 else f"{pages[0]}–{pages[-1]}"
        return f"{self.chapter_code} · {self.section} · p. {span}"


@dataclass
class DraftQuestion:
    chapter_code: str
    number: int
    prompt: str
    options: list[str]
    book_page: int | None
    # The précis prints no answer key; an ANO sets the answer before approval.
    correct_index: int | None = None
    status: str = "draft"


@dataclass
class Chapter:
    code: str
    title: str
    pages: list[Page] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

def to_page(pdf_page: int, text: str) -> Page:
    """Strip the leading printed page number, if present."""
    lines = text.splitlines()
    book_page = None
    if lines and re.fullmatch(r"\s*\d{1,4}\s*", lines[0]):
        book_page = int(lines[0])
        lines = lines[1:]
    return Page(pdf_page=pdf_page, book_page=book_page, text="\n".join(lines).strip())


def fill_book_pages(pages: list[Page]) -> list[Page]:
    """Chapter opening pages print no number; infer it from the next numbered page."""
    out = list(pages)
    for i in range(len(out) - 1, -1, -1):
        if out[i].book_page is None and i + 1 < len(out) and out[i + 1].book_page is not None:
            out[i] = Page(out[i].pdf_page, out[i + 1].book_page - 1, out[i].text)
    return out


# ---------------------------------------------------------------------------
# Master index
# ---------------------------------------------------------------------------

_INDEX_ROW = re.compile(
    rf"^\s*\d+\.\s+(?P<code>[A-Z]+-{ROMAN})\s+(?P<rest>.+?)\s*$"
)
_KIND = re.compile(r"^[TP]\d*$")
ACRONYMS = {"CAPF", "FC", "BC", "GPS", "NCC", "IAF", "MR", "RT"}
_SMALL = {"of", "and", "to", "the", "its", "in", "a", "an", "for", "on", "&"}


def smart_title(text: str) -> str:
    out: list[str] = []
    for i, word in enumerate(text.split()):
        core = word.strip("():,–-").upper()
        after_break = i == 0 or out[-1].endswith((":", "–", "-"))
        if core in ACRONYMS or re.fullmatch(ROMAN, core) and core:
            out.append(word.upper())
        elif not after_break and word.lower() in _SMALL:
            out.append(word.lower())
        else:
            lead = len(word) - len(word.lstrip("("))
            out.append(word[:lead] + word[lead:lead + 1].upper() + word[lead + 1:].lower())
    return " ".join(out)


def _clean_index_lines(text: str) -> list[str]:
    """Drop the totals block, whose stray "T31"/"P16" tokens wrap around the TOTAL line."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("TOTAL"):
            end = i - 1 if i > 0 and _KIND.match(lines[i - 1].strip()) else i
            return lines[:end]
    return lines


def parse_master_index(text: str) -> list[IndexEntry]:
    """Parse MASTER INDEX rows. Titles may wrap onto following lines.

    Each row ends with year-wise period counts, a type and a page number. The
    type column carries the theory/practical split ("T2" + "P1" = 2 theory,
    1 practical); a bare "T" or "P" means all periods are of that type.
    """
    entries: list[IndexEntry] = []
    lines = _clean_index_lines(text)
    i = 0
    while i < len(lines):
        m = _INDEX_ROW.match(lines[i])
        if not m:
            i += 1
            continue
        code, rest = m.group("code"), m.group("rest")
        tail = re.search(r"(?P<nums>(?:\d+\s+){0,2})(?P<kind>[TP]\d*)\s+(?P<page>\d+)$", rest)
        title = rest[: tail.start()].strip() if tail else rest
        nums = [int(n) for n in tail.group("nums").split()] if tail else []
        kinds = [tail.group("kind")] if tail else []
        page = int(tail.group("page")) if tail else 0
        j = i + 1
        while j < len(lines) and not _INDEX_ROW.match(lines[j]) and not lines[j].lstrip().startswith("(CODE"):
            cont = lines[j].strip()
            if not cont or cont.startswith(("SER", "NO ", "Yr")):
                break
            extra = re.match(r"^(?P<words>.*?)\s*(?P<kind>[TP]\d+)?$", cont)
            if extra.group("words"):
                title += " " + extra.group("words")
            if extra.group("kind"):
                kinds.append(extra.group("kind"))
            j += 1
        theory, practical = _split_kinds(kinds, sum(nums))
        entries.append(IndexEntry(code, smart_title(title), theory, practical, page))
        i = j
    return entries


_GROUP = re.compile(r"\(CODE-\s*(?P<code>[A-Z]+)\)\s*(?P<name>.+?)\s*\((?P<periods>\d+)\s+PERIODS\)")


def parse_index_groups(text: str) -> dict[str, str]:
    """Map subject-group codes to names, e.g. {"MR": "Map Reading"}."""
    return {m.group("code"): smart_title(m.group("name")) for m in _GROUP.finditer(text)}


def _split_kinds(kinds: list[str], total: int) -> tuple[int, int]:
    theory = practical = 0
    counted = False
    for k in kinds:
        if len(k) > 1:
            counted = True
            if k[0] == "T":
                theory += int(k[1:])
            else:
                practical += int(k[1:])
    if counted:
        return theory, practical
    if kinds == ["P"]:
        return 0, total
    return total, 0


# ---------------------------------------------------------------------------
# Chapters and passages
# ---------------------------------------------------------------------------

_CHAPTER = re.compile(rf"CHAPTER\s+(?P<code>[A-Z]+\s+{ROMAN})\s*:\s*(?P<title>.+)")
_SECTION = re.compile(r"^(?:PART\s+[IVX]+\s*[:\-–]\s*.+|INTRODUCTION|CONCLUSION|SUMMARY)\s*$")
_NOISE = re.compile(r"^(?:[A-Z &()/]+\((?:JD/JW|SD/SW)\)|DID YOU KNOW\?)$")


_INDEX_PAGE = re.compile(r"SUBJECT (?:CODE AND CONTENT|OF CONTENT)|CHAPTER WISE INDEX|MASTER INDEX")


def split_chapters(pages: list[Page], index: list[IndexEntry] | None = None,
                   continues: str | None = None) -> list[Chapter]:
    """Group pages by chapter. Titles come from the index when available,
    because chapter headings can wrap across lines.

    ``continues`` names the chapter a volume opens in the middle of (e.g. Part 2
    of a précis starting with the rest of "AF IV"), so those pages aren't lost.
    """
    titles = {e.code.replace("-", " "): e.title for e in index or []}
    chapters: list[Chapter] = []
    if continues:
        chapters.append(Chapter(continues, titles.get(continues, continues)))
    for page in pages:
        if _INDEX_PAGE.search(page.text):
            continue  # chapter-wise index pages list every chapter heading
        m = _CHAPTER.search(page.text)
        if m:
            code = " ".join(m.group("code").split())
            chapters.append(Chapter(code, titles.get(code, smart_title(m.group("title").strip()))))
        if chapters:
            chapters[-1].pages.append(page)
    return chapters


def chapter_body(chapter: Chapter) -> tuple[list[tuple[int | None, str]], list[tuple[int | None, str]]]:
    """Split a chapter's lines into (content lines, assessment lines), each tagged with its book page."""
    content: list[tuple[int | None, str]] = []
    assessment: list[tuple[int | None, str]] = []
    in_assessment = False
    for page in chapter.pages:
        for line in page.text.splitlines():
            if "ASSESSMENT EXERCISE" in line:
                in_assessment = True
                continue
            (assessment if in_assessment else content).append((page.book_page, line))
    return content, assessment


def build_passages(chapter: Chapter, max_chars: int = 1400) -> list[Passage]:
    content, _ = chapter_body(chapter)
    passages: list[Passage] = []
    section = "INTRODUCTION"
    buf: list[str] = []
    pages: list[int] = []
    started = False

    def flush() -> None:
        text = " ".join(" ".join(buf).split())
        title = smart_title(section)
        if text and len(text) < 200 and passages and passages[-1].section == title:
            # A short tail (e.g. the end of a sentence cut at the size limit) reads
            # better as part of the passage it came from.
            last = passages[-1]
            last.text = f"{last.text} {text}"
            last.book_pages = sorted(set(last.book_pages) | set(pages))
        elif text:
            passages.append(Passage(chapter.code, chapter.title, title, sorted(set(pages)), text))
        buf.clear()
        pages.clear()

    for book_page, raw in content:
        line = raw.strip()
        if not line or _NOISE.match(line) or _CHAPTER.search(line):
            continue
        if line.startswith("TEACHING INSTRUCTIONS"):
            started = False  # skip the instructor block until the first section heading
            continue
        if _SECTION.match(line):
            flush()
            section = line
            started = True
            continue
        if not started:
            continue
        # Start a new passage at a numbered paragraph once the buffer is big enough.
        if re.match(r"^\d+\.\s", line) and sum(len(b) for b in buf) >= max_chars * 0.6:
            flush()
        buf.append(line)
        if book_page is not None:
            pages.append(book_page)
        if sum(len(b) for b in buf) >= max_chars:
            flush()
    flush()
    return passages


# ---------------------------------------------------------------------------
# Assessment MCQs
# ---------------------------------------------------------------------------

_Q = re.compile(r"^Q(?P<n>\d+)\.\s*(?P<text>.*)$")
# An option marker: "(a)" — or "(b " where the book's closing bracket is missing.
_MARK = re.compile(r"\(([a-f])(?:\)|\s)\s*")
_END_MCQS = re.compile(r"^(?:Short|Long)\s+Answers?\b", re.I)
LETTERS = "abcdef"


def split_options(line: str, expected: str) -> list[tuple[str, str]]:
    """Split a line into (letter, text) options, accepting markers only in order.

    Markers are taken strictly in sequence starting from ``expected``, so text
    such as "(c) Both (a) and (b)" keeps "(a) and (b)" inside option (c).
    Returns an empty list if the line does not start with the expected marker.
    """
    found: list[tuple[str, int, int]] = []  # letter, marker start, text start
    pos, want = 0, expected
    while want:
        m = None
        for cand in _MARK.finditer(line, pos):
            if cand.group(1) == want:
                m = cand
                break
        if m is None or (not found and line[: m.start()].strip()):
            break
        found.append((want, m.start(), m.end()))
        pos = m.end()
        nxt = LETTERS.index(want) + 1
        want = LETTERS[nxt] if nxt < len(LETTERS) else ""
    return [(letter, line[start:(found[i + 1][1] if i + 1 < len(found) else len(line))].strip())
            for i, (letter, _, start) in enumerate(found)]


_TRAILING_MARK = re.compile(r"\s*\([a-f]\)\s*$")
_ANY_MARK = re.compile(r"\([a-f]\)")


def _fix_layouts(options: list[str]) -> list[str]:
    """Repair two layouts the strict parser can't see on its own.

    * Two columns: "(a) X (c) Y" then "(b) Z (d) W" arrive as two options
      "X (c) Y" and "Z (d) W"; they are re-split into a, b, c, d.
    * A misprinted letter on the last option, e.g. "(c) P (c) Q" where (d) was meant.
    """
    if len(options) == 2:
        left = re.split(r"\s*\(c\)\s*", options[0], maxsplit=1)
        right = re.split(r"\s*\(d\)\s*", options[1], maxsplit=1)
        if len(left) == 2 and len(right) == 2:
            options = [left[0], right[0], left[1], right[1]]
    if 2 <= len(options) < 4:
        own = LETTERS[len(options) - 1]
        nxt = LETTERS[len(options)]
        parts = re.split(rf"\s*\((?:{own}|{nxt})\)\s*", options[-1], maxsplit=1)
        if len(parts) == 2 and all(parts):
            options = options[:-1] + parts
    # A lone stray marker at the end ("2 km (b)") is layout debris; one that ends
    # a phrase like "Both (a) and (b)" is part of the answer.
    return [_TRAILING_MARK.sub("", o) if len(_ANY_MARK.findall(o)) == 1 else o for o in options]


def parse_mcqs(chapter: Chapter) -> list[DraftQuestion]:
    """MCQs from the assessment exercise. Fill-in-the-blank questions (no
    options) are skipped, as are short- and long-answer questions."""
    _, assessment = chapter_body(chapter)
    questions: list[DraftQuestion] = []
    current: dict | None = None

    pending: list[str] = []  # lines after the options: a wrapped option, or a lost question's prompt

    def finish() -> None:
        if not current:
            return
        if pending and not current["closed"]:
            current["options"][-1] += " " + " ".join(pending)
        pending.clear()
        options = _fix_layouts([" ".join(o.split()) for o in current["options"] if o.strip()])
        if len(options) >= 2:
            questions.append(DraftQuestion(
                chapter.code, current["n"], " ".join(current["prompt"].split()), options, current["page"]))

    for book_page, raw in assessment:
        line = raw.strip()
        if not line or line.startswith("Multiple Choice Questions"):
            continue
        if _END_MCQS.match(line):
            break
        q = _Q.match(line)
        if q:
            finish()
            current = {"n": int(q.group("n")), "prompt": q.group("text"), "options": [],
                       "page": book_page, "closed": False}
            continue
        if current is None or current["closed"]:
            continue
        expected = LETTERS[len(current["options"])] if len(current["options"]) < len(LETTERS) else ""
        opts = split_options(line, expected) if expected else []
        if opts:
            if pending:
                current["options"][-1] += " " + " ".join(pending)
                pending.clear()
            current["options"].extend(text for _, text in opts)
        elif current["options"] and split_options(line, "a"):
            # A fresh "(a)" after the options means the next question's "Qn." line
            # is missing from the PDF; the held lines were its prompt. Stop rather
            # than merge two questions.
            pending.clear()
            current["closed"] = True
        elif current["options"]:
            pending.append(line)  # decided by the next line
        else:
            current["prompt"] += " " + line  # wrapped prompt
    finish()
    return questions
