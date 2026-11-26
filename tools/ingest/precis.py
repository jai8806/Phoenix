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
_NOISE = re.compile(r"^(?:[A-Z ()/]+\(JD/JW\)|DID YOU KNOW\?)$")


def split_chapters(pages: list[Page], index: list[IndexEntry] | None = None) -> list[Chapter]:
    """Group pages by chapter. Titles come from the index when available,
    because chapter headings can wrap across lines."""
    titles = {e.code.replace("-", " "): e.title for e in index or []}
    chapters: list[Chapter] = []
    for page in pages:
        m = _CHAPTER.search(page.text)
        if m and "INDEX" not in page.text[: m.start()]:
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
        if text:
            passages.append(Passage(chapter.code, chapter.title, smart_title(section),
                                    sorted(set(pages)), text))
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
_OPT = re.compile(r"\(([a-d])\)\s*")


def parse_mcqs(chapter: Chapter) -> list[DraftQuestion]:
    _, assessment = chapter_body(chapter)
    questions: list[DraftQuestion] = []
    current: dict | None = None

    def finish() -> None:
        if current and len(current["options"]) >= 2:
            questions.append(DraftQuestion(
                chapter.code, current["n"], " ".join(current["prompt"].split()),
                [" ".join(o.split()) for o in current["options"]], current["page"],
            ))

    for book_page, raw in assessment:
        line = raw.strip()
        if not line or line == "Multiple Choice Questions":
            continue
        if "Answer" in line and "Questions" in line:  # short/long answer sections end the MCQs
            break
        q = _Q.match(line)
        if q:
            finish()
            current = {"n": int(q.group("n")), "prompt": q.group("text"), "options": [], "page": book_page}
            continue
        if current is None:
            continue
        if _OPT.match(line):
            # One or more options on this line: "(a) X (b) Y".
            parts = _OPT.split(line)[1:]
            for letter, value in zip(parts[0::2], parts[1::2]):
                current["options"].append(value.strip())
        elif current["options"]:
            current["options"][-1] += " " + line  # wrapped option
        else:
            current["prompt"] += " " + line  # wrapped prompt
    finish()
    return questions
