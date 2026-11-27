"""Exam weightage and high-yield chapters for B and C Certificate (Army SD/SW).

    python3 tools/ingest/analyze_pyq.py --out app/lib/data/exam/cert_insights.dart

Two inputs:
  * the marks blueprint, read from the 2024 B Cert paper (KAR & GOA
    Directorate) and checked against its question numbering (2 marks each);
  * every bank and paper question (content/build/qb_*, paper_*), matched to
    the précis chapter it is about with keyword search restricted to the
    question's subject, to show which chapters questions keep coming from.

Only numbers and chapter titles go into the app; no précis or question text.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ask import BM25  # noqa: E402

# Subject -> (précis group codes in the SD/SW books, section names used in banks and papers)
SUBJECTS = {
    "Personality Development": (["PDLS"], ["Personality Development"]),
    "Social Service & Community Development": (["SA"], ["Social Service & Community Development (SSCD)", "PMJAY"]),
    "Weapon Training": (["WT"], ["Weapon Training"]),
    "Health & Hygiene": (["H"], ["Health and Hygiene"]),
    "National Integration & Awareness": (["NI"], ["National Integration", "NCC Integration and Awareness"]),
    "Leadership": (["L"], ["Leadership"]),
    "Disaster Management": (["DM"], ["Disaster Management"]),
    "Adventure": (["ADV"], ["Adventure"]),
    "Border & Coastal Areas": ([], ["Border And Coastal Areas"]),
    "NCC General": (["N"], ["NCC General"]),
    "Obstacle Training": ([], ["Obstacle Training"]),
    "Environment Awareness": (["E"], ["Environmental Awareness And Conservation"]),
    "Drill": (["FD"], ["Drill"]),
    "Map Reading": (["MR"], ["Map Reading (MR)", "Map Reading"]),
    "Field Craft & Battle Craft": (["FC/BC"], ["Field Craft And Battle Craft (Fc & Bc)", "Field Craft & Battle Craft (Fc & Bc)"]),
    "Armed Forces": (["AF"], ["Armed Forces"]),
    "Military History": (["MH"], ["Military History (MH)", "Military History"]),
    "Infantry Weapons & Equipment": (["INF"], ["Introduction To Infantry Weapons And Equipment", "Infantry Weapons & Equipment"]),
    "Communication": (["C"], ["Communication"]),
}

# Marks per subject from real papers, checked against question numbering
# (2 marks each). Notes say where a number is inferred.
EXAMS = {
    "bCertInsights": {
        "exam": "B Certificate",
        "source": "B Cert papers 2024 and 2026 (Sets 1 and 2), answer sheet 2025-26 · KAR & GOA Directorate · Army SD/SW",
        "negative": 0.5, "negative_note": "−0.5 per wrong answer (2025-26 answer sheet)",
        "marks": [
            ("common", "Personality Development", 60, ""), ("common", "Social Service & Community Development", 32, ""),
            ("common", "Weapon Training", 30, ""), ("common", "Health & Hygiene", 26, ""),
            ("common", "National Integration & Awareness", 20, ""),
            ("common", "Leadership", 18, "inferred from question numbers"),
            ("common", "Disaster Management", 18, ""), ("common", "Adventure", 16, ""),
            ("common", "Border & Coastal Areas", 8, ""), ("common", "NCC General", 6, ""),
            ("common", "Obstacle Training", 6, ""),
            ("common", "Environment Awareness", 0, "not in the 2024 paper"),
            ("common", "Drill", 0, "tested in the practical, not the written paper"),
            ("special", "Map Reading", 24, ""), ("special", "Field Craft & Battle Craft", 24, ""),
            ("special", "Armed Forces", 20, ""), ("special", "Military History", 20, ""),
            ("special", "Infantry Weapons & Equipment", 16, ""), ("special", "Communication", 6, ""),
        ],
    },
    "cCertInsights": {
        "exam": "C Certificate",
        "source": "C Cert paper 2024-25 · Army SD/SW (scanned paper, read with OCR)",
        "negative": 0.5, "negative_note": "−0.5 per wrong answer assumed, as in B Cert; confirm with your ANO",
        "marks": [
            ("common", "Personality Development", 70, ""), ("common", "Social Service & Community Development", 36, ""),
            ("common", "Health & Hygiene", 28, "heading unreadable; from question numbers and topics"),
            ("common", "Disaster Management", 22, ""), ("common", "Leadership", 20, ""),
            ("common", "Environment Awareness", 20, ""),
            ("common", "Obstacle Training", 14, "heading unreadable; questions are on obstacles"),
            ("common", "Weapon Training", 10, ""), ("common", "National Integration & Awareness", 10, ""),
            ("common", "Border & Coastal Areas", 10, ""),
            ("common", "NCC General", 0, "not in the 2024-25 paper"), ("common", "Adventure", 0, "not in the 2024-25 paper"),
            ("common", "Drill", 0, "tested in the practical, not the written paper"),
            ("special", "Field Craft & Battle Craft", 32, ""), ("special", "Map Reading", 30, ""),
            ("special", "Military History", 20, ""), ("special", "Infantry Weapons & Equipment", 12, ""),
            ("special", "Armed Forces", 10, ""), ("special", "Communication", 6, ""),
        ],
    },
}


def dart_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", type=Path, default=Path("content/build"))
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    for spec in EXAMS.values():
        assert sum(m for p, _, m, _ in spec["marks"] if p == "common") == 240, spec["exam"]
        assert sum(m for p, _, m, _ in spec["marks"] if p == "special") == 110, spec["exam"]

    # Précis passages from the SD/SW books, grouped by lesson-code prefix.
    passages = []
    titles: dict[str, str] = {}
    for name in ("army_sd_sw_2025", "common_sd_sw_2025"):
        for line in (args.build / name / "passages.jsonl").open():
            p = json.loads(line)
            passages.append(p)
            titles[p["chapter_code"]] = p["chapter_title"]
    by_group: dict[str, list[int]] = defaultdict(list)
    for i, p in enumerate(passages):
        by_group[p["chapter_code"].rsplit("-", 1)[0]].append(i)
    bm = BM25([f"{p['section']} {p['text']}" for p in passages])

    dirs = [d for pat in ("qb_*", "paper_*", "practice_*") for d in sorted(args.build.glob(pat)) if d.is_dir()]
    questions = [json.loads(l) for d in dirs
                 for l in (d / "questions.jsonl").open()]
    section_to_subject = {sec.lower(): name for name, (_, secs) in SUBJECTS.items() for sec in secs}

    chapter_hits: dict[str, Counter] = defaultdict(Counter)
    bank_counts: Counter = Counter()
    matched = 0
    for q in questions:
        subject = section_to_subject.get(q["chapter_code"].lower())
        if subject is None:
            continue
        groups = SUBJECTS[subject][0]
        bank_counts[subject] += 1
        candidates = [i for g in groups for i in by_group.get(g, [])]
        if not candidates:
            continue
        scores = bm.scores(q["prompt"] + " " + " ".join(q["options"]))
        best = max(candidates, key=lambda i: scores[i])
        if scores[best] > 0:
            chapter_hits[subject][passages[best]["chapter_code"]] += 1
            matched += 1

    lines = [
        "// GENERATED by tools/ingest/analyze_pyq.py. Do not edit by hand.",
        f"// High-yield chapters: {matched} bank and paper questions matched to précis chapters.",
        "",
        "import 'insights.dart';",
        "",
    ]
    for const, spec in EXAMS.items():
        lines += [
            f"const {const} = ExamInsights(",
            f"  exam: {dart_str(spec['exam'])},",
            f"  source: {dart_str(spec['source'])},",
            "  totalMarks: 350,",
            "  questionCount: 175,",
            "  durationMinutes: 180,",
            "  passRule: '33% in each paper and in aggregate',",
            f"  negativeMarks: {spec['negative']},",
            f"  negativeNote: {dart_str(spec['negative_note'])},",
            f"  questionsAnalysed: {matched},",
            "  subjects: [",
        ]
        for paper, subject, marks, note in spec["marks"]:
            groups, sections = SUBJECTS[subject]
            hits = chapter_hits.get(subject, Counter())
            total = sum(hits.values())
            top = [(code, n) for code, n in hits.most_common(5) if total and n / total >= 0.08]
            lines.append(
                f"    SubjectInsight(paper: ExamPaper.{paper}, name: {dart_str(subject)}, marks: {marks}, "
                f"groupCodes: [{', '.join(dart_str(g) for g in groups)}], bankQuestions: {bank_counts[subject]}, "
                f"bankSections: [{', '.join(dart_str(x) for x in sections)}], note: {dart_str(note)}, topChapters: ["
            )
            for code, n in top:
                lines.append(f"      ChapterShare(code: {dart_str(code)}, title: {dart_str(titles.get(code, code))}, "
                             f"share: {n / total:.2f}),")
            lines.append("    ]),")
        lines += ["  ],", ");", ""]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines))
    print(f"Wrote {args.out}: {len(EXAMS)} exams; {matched} of {len(questions)} questions matched to chapters")


if __name__ == "__main__":
    main()
