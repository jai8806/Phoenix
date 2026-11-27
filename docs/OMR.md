# OMR mock exams

Mocks that run like the real B and C Certificate papers: questions on the
cadets' phones, answers on a printed OMR sheet, sheets photographed and read
by the phone, marks from the server.

## For the ANO

1. **Command Center → Tests → New test → OMR mock (real exam).** Choose B or
   C Certificate. Questions are picked from approved questions in the 2026
   paper's sections (B: Weapon Training 15; Miscellaneous 105; Specialised 55;
   175 questions, 350 marks, 3 hours, +2 / −0.5). If a section is short of
   approved questions, those sheet numbers stay unused; approve more in the
   review queue first.
2. **Open the test → Print OMR sheet.** One A4 sheet per cadet, printed at
   actual size (no "fit to page"). The sheet follows the DGNCC layout and adds
   four black corner squares, a sheet code and SET A1 / A2.
3. **Start exam** when everyone is seated with a sheet and a pen. Cadets see
   the paper at once. Half get Set A1 and half Set A2 (same questions, a
   different order within each paper).
4. After the paper (3 hours), cadets have the upload window you chose
   (15 / 20 / 30 minutes) to photograph their sheets.
5. **Results:** scores, each cadet's set, unclear marks and how many they
   confirmed by hand, and the photo of every sheet to check by eye.
   **Unit performance** shows cadets at risk of failing a paper (33% in each),
   the unit's weak subjects and a cadet-by-subject heatmap.

## For cadets

Learn → the mock → wait for the start → read the paper on the phone and
darken answers on the sheet (one per question; two marks count as wrong) →
**Finished · scan my sheet** → photograph the sheet flat, all four corner
squares in view → check the amber marks the scanner wasn't sure of → Submit.
The score and paper results show at once; the answer key opens when the exam
closes. **My progress** tracks scores and weak subjects across tests.

## How the scanner works

`lib/domain/omr/`: `omr_layout.dart` holds the sheet geometry used by both
the PDF (`lib/features/omr/omr_sheet_pdf.dart`) and the scanner
(`omr_scanner.dart`): find the four corner squares (dark, on white paper),
map the sheet with a homography, choose the rotation by where the printed
bubble outlines fall, read the sheet code (16 bits + CRC-8), then judge each
question against the paper around it. Faint, rubbed-out and double marks are
flagged for the cadet to confirm.

Tests: `test/omr/` draws filled sheets and "photographs" them (tilt, turns,
shadow, blur, noise, JPEG, pen colour). `STRESS=100 flutter test
test/omr/omr_stress_test.dart` runs a random batch; `tool/omr_check.dart`
scans a real photo. Before the first real mock, try 5 to 10 printed sheets
photographed on your own phones.
