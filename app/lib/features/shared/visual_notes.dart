import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';

/// A picture that explains one high-yield topic at a glance. Drawn in the
/// app (works offline, no uploads) and checked against the précis.
class VisualNote {
  const VisualNote({
    required this.id,
    required this.title,
    required this.chapters,
    required this.source,
    required this.build,
    this.remember,
  });

  final String id;
  final String title;

  /// Chapter codes this picture belongs to, e.g. {'MR III'}.
  final Set<String> chapters;
  final String source;

  /// One line to remember it by.
  final String? remember;
  final WidgetBuilder build;
}

List<VisualNote> visualNotesFor(String chapterCode) => [for (final n in visualNotes) if (n.chapters.contains(chapterCode)) n];

final visualNotes = <VisualNote>[
  VisualNote(
    id: 'ncc_org',
    title: 'How the NCC is organised',
    chapters: {'NCC I'},
    remember: 'MoD → DG NCC → 17 Directorates → Groups → Units → your college',
    source: 'NB & CP SD/SW (Oct 2025) · NCC I',
    build: (_) => const _Ladder(steps: [
      ('Ministry of Defence', 'The NCC works under the MoD'),
      ('HQ DG NCC, New Delhi', 'DG NCC: Lt Gen Virendra Vats (since 1 Oct 2025)'),
      ('17 Directorates', 'One per state / group of states, under an ADG or DDG'),
      ('Group Headquarters', 'Several in each Directorate, under a Group Commander'),
      ('NCC Units (Battalions)', 'Army, Navy or Air units, under a Commanding Officer'),
      ('College / School troop', 'Led by the ANO, run day to day by the CSUO / SUO'),
    ]),
  ),
  VisualNote(
    id: 'ncc_basics',
    title: 'NCC at a glance',
    chapters: {'NCC I', 'NCC II'},
    remember: '15 July 1948 · "Unity and Discipline" · NCC Day = 4th Sunday of November',
    source: 'Common Subject SD/SW · N-1; NB & CP SD/SW (Oct 2025) · NCC I',
    build: (_) => const _NccBasics(),
  ),
  VisualNote(
    id: 'cadet_ranks',
    title: 'Cadet ranks, highest first',
    chapters: {'NCC I', 'NCC II', 'PDLS II'},
    remember: 'Highest cadet rank: CSUO / SUO',
    source: 'Common Subject SD/SW · N-5 · Cadet Appointments',
    build: (_) => const _CadetRanks(),
  ),
  VisualNote(
    id: 'service_ranks',
    title: 'Equivalent officer ranks',
    chapters: {'AF II', 'AF I'},
    remember: 'Read across a row: the three ranks are equal',
    source: 'Special Subject (Army) · AF II · Badges of Ranks',
    build: (_) => const _RankTable(),
  ),
  VisualNote(
    id: 'gallantry',
    title: 'Gallantry awards, highest first',
    chapters: {'AF III', 'MH VII'},
    remember: 'War: Param Vir, Maha Vir, Vir. Peace: Ashoka, Kirti, Shaurya',
    source: 'Special Subject (Army) · AF III · Honours and Awards',
    build: (_) => const _Gallantry(),
  ),
  VisualNote(
    id: 'types_of_north',
    title: 'The three norths',
    chapters: {'MR III', 'MR IV', 'MR VI'},
    remember: 'True never changes · Grid = map lines · Magnetic = compass, keeps shifting, not on the map',
    source: 'Special Subject (Army) · MR III · p. 185–186',
    build: (_) => const _ThreeNorths(),
  ),
  VisualNote(
    id: 'map_colours',
    title: 'Colours on a topographical map',
    chapters: {'MR I', 'MR II'},
    remember: 'Blue water · Brown contours · Green trees · Red man-made',
    source: 'Special Subject (Army) · MR I · Conventional Signs; MR II · Contours',
    build: (_) => const _MapColours(),
  ),
  VisualNote(
    id: 'grid_reference',
    title: 'Reading a grid reference',
    chapters: {'MR I', 'MR V', 'MR VI'},
    remember: 'Eastings first, then Northings: along the corridor, then up the stairs',
    source: 'Special Subject (Army) · MR I · Part IV: Grid References',
    build: (_) => const _GridReference(),
  ),
  VisualNote(
    id: 'section_formations',
    title: 'Section formations',
    chapters: {'FCBC VII', 'FCBC I'},
    remember: 'Narrow path → single file · open ground → arrowhead · night, open country → diamond',
    source: 'Special Subject (Army) · FCBC VII · Part I',
    build: (_) => const _Formations(),
  ),
  VisualNote(
    id: 'grit',
    title: 'Fire control orders: GRIT',
    chapters: {'FCBC I', 'FCBC II', 'FCBC VI', 'FCBC VII'},
    remember: 'Group → Range → Indication → Type of fire',
    source: 'Special Subject (Army) · FC/BC · Sequence of Fire Control Orders',
    build: (_) => const _Grit(),
  ),
  VisualNote(
    id: 'knots',
    title: 'Knots and what each is for',
    chapters: {'FCBC IV'},
    remember: 'Reef joins equal ropes · Bowline makes a loop that will not slip · Clove hitch ties to a spar',
    source: 'Special Subject (Army) · FCBC IV · Knots, Lashings and Stretchers',
    build: (_) => const _Knots(),
  ),
  VisualNote(
    id: 'phonetic',
    title: 'Phonetic alphabet',
    chapters: {'MC II', 'MC I'},
    remember: 'Spell names on the radio letter by letter: R-V = Romeo Victor',
    source: 'Common Subject · MC II · Part II: Phonetic Alphabets',
    build: (_) => const _Phonetic(),
  ),
  VisualNote(
    id: 'cpr',
    title: 'CPR in five steps',
    chapters: {'PMW IV', 'PMW V'},
    remember: '30 compressions : 2 breaths · about 100 a minute',
    source: 'Basics of First Aid (H-5) · CPR Technique',
    build: (_) => const _Cpr(),
  ),
  VisualNote(
    id: 'dm_structure',
    title: 'Who manages a disaster',
    chapters: {'DM I', 'DM III', 'DM VII'},
    remember: 'NDMA: Prime Minister · SDMA: Chief Minister · DDMA: District Collector',
    source: 'Common Subject · DM · Organisation of NDMA',
    build: (_) => const _Ladder(steps: [
      ('NDMA (national)', 'Headed by the Prime Minister. Lays down policies and approves national plans'),
      ('SDMA (state)', 'Headed by the Chief Minister. Approves the State Plan'),
      ('DDMA (district)', 'Headed by the District Collector / DC / DM. Plans and carries out relief'),
      ('NCC cadets', 'Help the local administration: relief, first aid, traffic and crowd control'),
    ]),
  ),
];

// ---------------------------------------------------------------------------
// Cards and the full-screen viewer
// ---------------------------------------------------------------------------

/// A picture note in full, with its title and source. Tap to zoom.
class VisualNoteCard extends StatelessWidget {
  const VisualNoteCard(this.note, {super.key});

  final VisualNote note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openVisualNote(context, note),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_mosaic_outlined, size: 18, color: c.primary),
              const SizedBox(width: Space.xs),
              Expanded(child: Text(note.title, style: t.titleMedium)),
              Icon(Icons.zoom_out_map, size: 18, color: c.onSurfaceVariant),
            ]),
            const SizedBox(height: Space.md),
            note.build(context),
            if (note.remember != null) ...[
              const SizedBox(height: Space.md),
              _Remember(note.remember!),
            ],
            const SizedBox(height: Space.sm),
            Text(note.source, style: t.labelSmall?.copyWith(color: c.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// A small tile for galleries: the picture scaled down, with its title.
class VisualNoteThumb extends StatelessWidget {
  const VisualNoteThumb(this.note, {super.key, this.width = 220});

  final VisualNote note;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => openVisualNote(context, note),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(
                color: c.surfaceContainerLow,
                padding: const EdgeInsets.all(Space.sm),
                child: IgnorePointer(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                    child: SizedBox(width: 380, child: Builder(builder: note.build)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.md),
              child: Text(note.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall),
            ),
          ]),
        ),
      ),
    );
  }
}

void openVisualNote(BuildContext context, VisualNote note) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _VisualNoteScreen(note: note)));
}

class _VisualNoteScreen extends StatelessWidget {
  const _VisualNoteScreen({required this.note});

  final VisualNote note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(note.title)),
      body: InteractiveViewer(
        maxScale: 4,
        child: ListView(padding: const EdgeInsets.all(Space.lg), children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                note.build(context),
                if (note.remember != null) ...[const SizedBox(height: Space.lg), _Remember(note.remember!)],
                const SizedBox(height: Space.md),
                Text('Source: ${note.source}', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
                const SizedBox(height: Space.xs),
                Text('Pinch to zoom.', style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Remember extends StatelessWidget {
  const _Remember(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(color: c.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, size: 18, color: c.onTertiaryContainer),
        const SizedBox(width: Space.sm),
        Expanded(child: Text(text, style: t.bodyMedium?.copyWith(color: c.onTertiaryContainer, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Top-down chain of boxes joined by arrows.
class _Ladder extends StatelessWidget {
  const _Ladder({required this.steps});

  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(children: [
      for (final (i, (name, note)) in steps.indexed) ...[
        if (i > 0) Icon(Icons.arrow_downward, size: 18, color: c.outline),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(
            color: Color.lerp(c.primaryContainer, c.surfaceContainerHigh, i / math.max(1, steps.length - 1)),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: t.titleSmall?.copyWith(color: c.onPrimaryContainer)),
            Text(note, style: t.bodySmall),
          ]),
        ),
      ],
    ]);
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Text(text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w700)),
      );
}

// ---------------------------------------------------------------------------
// The pictures
// ---------------------------------------------------------------------------

class _NccBasics extends StatelessWidget {
  const _NccBasics();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget fact(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: c.primary),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$label  ', style: t.labelLarge?.copyWith(color: c.onSurfaceVariant)),
                TextSpan(text: value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ])),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The flag: three equal vertical strips
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          height: 70,
          child: Row(children: [
            for (final (color, name) in const [(Color(0xFFD32F2F), 'Army'), (Color(0xFF0D2A6B), 'Navy'), (Color(0xFF4FA3E0), 'Air Force')])
              Expanded(
                child: Container(
                  color: color,
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(name, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text('NCC flag: three equal strips. Red, deep blue and light blue stand for the three services.', style: t.bodySmall),
      const SizedBox(height: Space.md),
      fact(Icons.flag_outlined, 'Raised', '15 July 1948, NCC Act (Act XXXI of 1948)'),
      fact(Icons.format_quote, 'Motto', '"Unity and Discipline" (Ekta aur Anushasan)'),
      fact(Icons.celebration_outlined, 'NCC Day', 'Fourth Sunday of November'),
      fact(Icons.timeline, 'Wings', 'Girls Division 1949 · Air Wing 1 Apr 1950 · Naval Wing 1952'),
      fact(Icons.person_outline, 'Head', 'DG NCC, Lt Gen Virendra Vats'),
    ]);
  }
}

class _CadetRanks extends StatelessWidget {
  const _CadetRanks();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const ranks = [
      ('CSUO / SUO', 'Company Senior Under Officer', 'Senior-most cadet; link between cadets and the ANO', 0),
      ('JUO', 'Junior Under Officer', 'Assists and understudies the CSUO', 0),
      ('CSM', 'Company Sergeant Major', 'Controls the company, keeps the parade state', 0),
      ('CQMS', 'Company Quarter Master Sergeant', 'Helps the ANO issue and receive stores', 0),
      ('Sgt', 'Sergeant', 'Controls a platoon', 3),
      ('Cpl', 'Corporal', 'Controls a section', 2),
      ('L/Cpl', 'Lance Corporal', 'Assists the corporal', 1),
      ('Cdt', 'Cadet', '', 0),
    ];
    return Column(children: [
      for (final (i, (short, name, job, chevrons)) in ranks.indexed)
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 6),
          decoration: BoxDecoration(
            color: i < 2 ? c.primaryContainer : c.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text('${i + 1}', textAlign: TextAlign.center, style: t.titleMedium?.copyWith(color: c.primary)),
            ),
            SizedBox(width: 92, child: Text(short, style: t.titleSmall)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (job.isNotEmpty) Text(job, style: t.bodySmall),
              ]),
            ),
            if (chevrons > 0) CustomPaint(size: const Size(28, 30), painter: _ChevronPainter(chevrons, c.onSurface)),
          ]),
        ),
    ]);
  }
}

class _ChevronPainter extends CustomPainter {
  _ChevronPainter(this.count, this.color);

  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final y = 6.0 + i * 8;
      canvas.drawPath(
          Path()
            ..moveTo(3, y)
            ..lineTo(size.width / 2, y + 7)
            ..lineTo(size.width - 3, y),
          p);
    }
  }

  @override
  bool shouldRepaint(_ChevronPainter old) => old.count != count || old.color != color;
}

class _RankTable extends StatelessWidget {
  const _RankTable();

  static const rows = [
    ('Field Marshal', 'Admiral of the Fleet', 'Marshal of the IAF'),
    ('General', 'Admiral', 'Air Chief Marshal'),
    ('Lieutenant General', 'Vice Admiral', 'Air Marshal'),
    ('Major General', 'Rear Admiral', 'Air Vice Marshal'),
    ('Brigadier', 'Commodore', 'Air Commodore'),
    ('Colonel', 'Captain', 'Group Captain'),
    ('Lieutenant Colonel', 'Commander', 'Wing Commander'),
    ('Major', 'Lieutenant Commander', 'Squadron Leader'),
    ('Captain', 'Lieutenant', 'Flight Lieutenant'),
    ('Lieutenant', 'Sub Lieutenant', 'Flying Officer'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget cell(String s, {TextStyle? style, Color? bg}) => Container(
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Text(s, style: style ?? t.bodySmall),
        );
    final head = t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700);
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Table(
        border: TableBorder.symmetric(inside: BorderSide(color: c.outlineVariant)),
        children: [
          TableRow(children: [
            cell('Army', style: head, bg: const Color(0xFF4E6B3A)),
            cell('Navy', style: head, bg: const Color(0xFF0D2A6B)),
            cell('Air Force', style: head, bg: const Color(0xFF2F7FC1)),
          ]),
          for (final (i, (a, n, f)) in rows.indexed)
            TableRow(
              decoration: BoxDecoration(color: i.isEven ? c.surfaceContainerHigh : c.surfaceContainerLow),
              children: [cell(a), cell(n), cell(f)],
            ),
        ],
      ),
    );
  }
}

class _Gallantry extends StatelessWidget {
  const _Gallantry();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget column(String head, String sub, List<String> awards, Color color) => Expanded(
          child: Column(children: [
            Text(head, style: t.titleSmall),
            Text(sub, style: t.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            for (final (i, a) in awards.indexed)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 4),
                padding: EdgeInsets.symmetric(vertical: 14.0 - i * 3, horizontal: 6),
                decoration: BoxDecoration(
                  color: Color.lerp(color, c.surface, i * 0.3),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Column(children: [
                  Text('${i + 1}', style: t.labelSmall?.copyWith(color: i == 0 ? Colors.white : c.onSurface)),
                  Text(a, textAlign: TextAlign.center, style: t.labelLarge?.copyWith(color: i == 0 ? Colors.white : c.onSurface)),
                ]),
              ),
          ]),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      column('In war', 'In the face of the enemy', ['Param Vir Chakra', 'Maha Vir Chakra', 'Vir Chakra'], const Color(0xFF8E3B2E)),
      const SizedBox(width: Space.md),
      column('In peace', 'Away from the battlefield', ['Ashoka Chakra', 'Kirti Chakra', 'Shaurya Chakra'], const Color(0xFF2E6B4E)),
    ]);
  }
}

class _ThreeNorths extends StatelessWidget {
  const _ThreeNorths();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    Widget key(Color color, String name, String what) => Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 14, height: 14, margin: const EdgeInsets.only(top: 3), color: color),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$name. ', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                TextSpan(text: what, style: t.bodyMedium),
              ])),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: CustomPaint(size: const Size(260, 200), painter: _NorthsPainter(c.onSurface, t.labelMedium!))),
      const SizedBox(height: Space.md),
      key(c.onSurface, 'True North (star)', 'Towards the geographic North Pole. Fixed, never changes. Solid black line on the map.'),
      key(const Color(0xFFC62828), 'Grid North (GN)', 'The north of the map\'s grid lines (red or purple). Differs from True North a little.'),
      key(const Color(0xFF1565C0), 'Magnetic North (half arrow)', 'Where the compass needle points. Keeps shifting, so it is not drawn on the map.'),
    ]);
  }
}

class _NorthsPainter extends CustomPainter {
  _NorthsPainter(this.ink, this.label);

  final Color ink;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Offset(size.width / 2, size.height - 10);
    const len = 150.0;
    void arrow(double deg, Color color, String text, {bool half = false, bool star = false}) {
      final a = (deg - 90) * math.pi / 180;
      final tip = base + Offset(math.cos(a), math.sin(a)) * len;
      final p = Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawLine(base, tip, p);
      final fill = Paint()..color = color;
      if (star) {
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? 11.0 : 4.5;
          final ang = -math.pi / 2 + i * math.pi / 5;
          final pt = tip + Offset(math.cos(ang), math.sin(ang)) * r - const Offset(0, 6);
          i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(path..close(), fill);
      } else {
        final back = Offset(math.cos(a), math.sin(a)) * -16;
        final side = Offset(-math.sin(a), math.cos(a)) * 7;
        final head = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo((tip + back + side).dx, (tip + back + side).dy)
          ..lineTo((tip + back).dx, (tip + back).dy);
        if (!half) head.lineTo((tip + back - side).dx, (tip + back - side).dy);
        canvas.drawPath(head..close(), fill);
      }
      final tp = TextPainter(text: TextSpan(text: text, style: label.copyWith(color: color, fontWeight: FontWeight.w700)), textDirection: TextDirection.ltr)
        ..layout();
      final at = base + Offset(math.cos(a), math.sin(a)) * (len + 22);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2 + (star ? 8 : 0)));
    }

    arrow(-14, const Color(0xFF1565C0), 'MN', half: true);
    arrow(0, ink, 'TN', star: true);
    arrow(9, const Color(0xFFC62828), 'GN');
  }

  @override
  bool shouldRepaint(_NorthsPainter old) => old.ink != ink;
}

class _MapColours extends StatelessWidget {
  const _MapColours();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const colours = [
      (Color(0xFF1E88E5), 'Blue', 'Perennial water bodies', true),
      (Color(0xFFF9D648), 'Yellow', 'Cultivated land', false),
      (Color(0xFF43A047), 'Green', 'Vegetation', true),
      (Color(0xFFF5F5F5), 'White', 'Barren land', false),
      (Color(0xFF8D5524), 'Brown', 'Contours and sand features', true),
      (Color(0xFF212121), 'Black', 'Names, lat. & long., dry water bodies', true),
      (Color(0xFFD32F2F), 'Red', 'Human-made features', true),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (color, name, what, dark) in colours)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(
              width: 76,
              padding: const EdgeInsets.symmetric(vertical: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: Colors.black12)),
              child: Text(name, style: t.labelMedium?.copyWith(color: dark ? Colors.white : Colors.black87, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: Space.md),
            Expanded(child: Text(what, style: t.bodyMedium)),
          ]),
        ),
      const SizedBox(height: Space.sm),
      Text('Contours', style: t.titleSmall),
      const SizedBox(height: 4),
      Text('Brown lines joining places of equal height. Every 5th one is the index contour (height written on it). '
          'They never meet or cross. Interval between two contours: 20 m.', style: t.bodyMedium),
    ]);
  }
}

class _GridReference extends StatelessWidget {
  const _GridReference();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Center(child: CustomPaint(size: const Size(270, 250), painter: _GridPainter(c.onSurface, c.primary, t.labelMedium!))),
      const SizedBox(height: Space.md),
      Text.rich(TextSpan(style: t.bodyMedium, children: const [
        TextSpan(text: 'Eastings', style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' are the vertical lines (khadi rekha); numbers grow towards the East. '),
        TextSpan(text: 'Northings', style: TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: ' are the horizontal lines (padi rekha); numbers grow towards the North.'),
      ])),
      const SizedBox(height: Space.sm),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        _Chip('4-figure: 2356 (the square)', c.primaryContainer),
        _Chip('6-figure: 233567 (the point)', c.tertiaryContainer),
      ]),
      const SizedBox(height: Space.sm),
      Text('A 4-figure reference names the square by the lines at its bottom-left corner. For 6 figures, split each side into tenths: '
          'the temple is 3/10 east of line 23 and 7/10 north of line 56.', style: t.bodySmall),
    ]);
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.ink, this.accent, this.label);

  final Color ink;
  final Color accent;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 26.0, cell = 95.0;
    final origin = Offset(left, size.height - bottom);
    final line = Paint()
      ..color = const Color(0xFFC62828)
      ..strokeWidth = 1.6;
    final faint = Paint()
      ..color = ink.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    void text(String s, Offset at, {Color? color, bool bold = false}) {
      final tp = TextPainter(
          text: TextSpan(text: s, style: label.copyWith(color: color ?? ink, fontWeight: bold ? FontWeight.w700 : null)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    // Tenths inside the square of interest
    for (var i = 1; i < 10; i++) {
      canvas.drawLine(origin + Offset(i * cell / 10, 0), origin + Offset(i * cell / 10, -cell), faint);
      canvas.drawLine(origin + Offset(0, -i * cell / 10), origin + Offset(cell, -i * cell / 10), faint);
    }
    for (var i = 0; i <= 2; i++) {
      canvas.drawLine(origin + Offset(i * cell, 0), origin + Offset(i * cell, -2 * cell), line);
      canvas.drawLine(origin + Offset(0, -i * cell), origin + Offset(2 * cell, -i * cell), line);
      text('${23 + i}', origin + Offset(i * cell, 12), bold: true);
      text('${56 + i}', origin + Offset(-16, -i * cell), bold: true);
    }
    // Shade the square 2356
    canvas.drawRect(Rect.fromPoints(origin, origin + const Offset(cell, -cell)), Paint()..color = accent.withValues(alpha: 0.08));
    // The temple at 3/10 E, 7/10 N
    final pt = origin + const Offset(cell * 0.3, -cell * 0.7);
    final guide = Paint()
      ..color = accent
      ..strokeWidth = 1.5;
    canvas.drawLine(origin + Offset(pt.dx - origin.dx, 0), pt, guide);
    canvas.drawLine(origin + Offset(0, pt.dy - origin.dy), pt, guide);
    canvas.drawCircle(pt, 6, Paint()..color = accent);
    text('Temple', pt + const Offset(30, -12), color: accent, bold: true);
    text('E →', origin + Offset(2 * cell + 26, 12));
    text('N ↑', origin + Offset(-16, -2 * cell - 18));
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.ink != ink || old.accent != accent;
}

class _Formations extends StatelessWidget {
  const _Formations();

  // Positions of the ten men, in a 0..1 box (x across, y down; the front is the top).
  static final shapes = <(String, List<Offset>, String)>[
    ('Single file', [for (var i = 0; i < 10; i++) Offset(0.5, 0.05 + i * 0.1)], 'Narrow paths, ditches, defiles. Good control; poor fire to the front.'),
    ('File', [for (var i = 0; i < 10; i++) Offset(i.isEven ? 0.35 : 0.65, 0.08 + (i ~/ 2) * 0.2)], 'Broad roads, wide nullahs. Good control; vulnerable to frontal fire.'),
    ('Arrowhead', [
      const Offset(0.5, 0.1),
      for (var i = 1; i <= 3; i++) ...[Offset(0.5 - i * 0.13, 0.1 + i * 0.2), Offset(0.5 + i * 0.13, 0.1 + i * 0.2)],
      const Offset(0.5, 0.55), const Offset(0.45, 0.8), const Offset(0.55, 0.8),
    ], 'Crossing open ground. Good depth and fire; control harder than diamond.'),
    ('Spearhead', [
      const Offset(0.5, 0.08), const Offset(0.38, 0.25), const Offset(0.62, 0.25),
      for (var i = 0; i < 7; i++) Offset(0.5, 0.4 + i * 0.09),
    ], 'Good depth, less vulnerable to enfilade fire. Control difficult; slower fire.'),
    ('Diamond', [
      const Offset(0.5, 0.08), const Offset(0.5, 0.2),
      const Offset(0.15, 0.45), const Offset(0.27, 0.5), const Offset(0.85, 0.45), const Offset(0.73, 0.5),
      const Offset(0.5, 0.45),
      const Offset(0.5, 0.78), const Offset(0.44, 0.9), const Offset(0.56, 0.9),
    ], 'Open country at night. Easy to control, good protection and observation.'),
    ('Extended line', [for (var i = 0; i < 10; i++) Offset(0.05 + i * 0.1, 0.5)], 'Brings down the most fire to the front quickly. Hardest to control.'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 3 : 2;
        final w = (box.maxWidth - (cols - 1) * Space.sm) / cols;
        return Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final (name, men, use) in shapes)
            Container(
              width: w,
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(color: c.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.md)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: t.titleSmall),
                const SizedBox(height: 4),
                AspectRatio(aspectRatio: 1.3, child: CustomPaint(painter: _MenPainter(men, c.primary, c.outline))),
                const SizedBox(height: 4),
                Text(use, style: t.bodySmall),
              ]),
            ),
        ]);
      }),
      const SizedBox(height: Space.sm),
      Text('Enemy / direction of advance is at the top. Dot positions are a sketch of a 10-man section.',
          style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
    ]);
  }
}

class _MenPainter extends CustomPainter {
  _MenPainter(this.men, this.color, this.arrowColor);

  final List<Offset> men;
  final Color color;
  final Color arrowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()
      ..color = arrowColor
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(size.width - 8, size.height * 0.4), Offset(size.width - 8, 6), a);
    canvas.drawPath(
        Path()
          ..moveTo(size.width - 8, 2)
          ..lineTo(size.width - 12, 10)
          ..lineTo(size.width - 4, 10)
          ..close(),
        Paint()..color = arrowColor);
    final p = Paint()..color = color;
    final r = math.min(size.width, size.height) * 0.045;
    for (final m in men) {
      canvas.drawCircle(Offset(m.dx * (size.width - 20) + 4, m.dy * size.height), r, p);
    }
  }

  @override
  bool shouldRepaint(_MenPainter old) => old.men != men || old.color != color;
}

class _Grit extends StatelessWidget {
  const _Grit();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const steps = [
      ('G', 'Group', 'Who fires: "No 1 Section" (whole section), "LMG Group" or "Rifle Group".', Color(0xFF2E7D32)),
      ('R', 'Range', 'Distance to the target, given before the target so everyone looks at the right area.', Color(0xFF1565C0)),
      ('I', 'Indication', 'Point out the target in the simplest way.', Color(0xFFEF6C00)),
      ('T', 'Type of fire', '"Fire!" at once, on further orders, or when the opportunity arises.', Color(0xFFC62828)),
    ];
    return Column(children: [
      for (final (i, (letter, word, what, color)) in steps.indexed) ...[
        if (i > 0) const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text(letter, style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(word, style: t.titleSmall),
              Text(what, style: t.bodyMedium),
            ]),
          ),
        ]),
      ],
      const SizedBox(height: Space.md),
      Text('Example: "No 1 Section · 300 · lone tree, half right · FIRE!"', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
    ]);
  }
}

class _Knots extends StatelessWidget {
  const _Knots();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const groups = [
      ('Stop a rope end slipping', Icons.radio_button_checked, [
        ('Thumb knot', 'Simplest stopper knot'),
        ('Overhand knot', 'Better grip, easy to undo'),
        ('Figure of eight', 'Like the thumb knot; easy to undo'),
      ]),
      ('Join two ropes', Icons.link, [
        ('Reef knot', 'Two ropes of equal thickness, securely'),
        ('Thief knot', 'Looks like a reef knot but is not one'),
        ("Fisherman's knot", 'Springy material: wire, fishing gut, vines'),
      ]),
      ('Make a loop', Icons.loop, [
        ('Bowline', 'A loop that will not slip on a rope end'),
      ]),
      ('Tie to a pole', Icons.horizontal_rule, [
        ('Clove hitch', 'Secures a rope to a spar; will not slip when taut'),
      ]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (head, icon, knots) in groups) ...[
        Row(children: [
          Icon(icon, size: 18, color: c.primary),
          const SizedBox(width: Space.xs),
          Text(head.toUpperCase(), style: t.labelMedium?.copyWith(color: c.primary, letterSpacing: 1)),
        ]),
        const SizedBox(height: 4),
        for (final (name, use) in knots)
          Padding(
            padding: const EdgeInsets.only(left: Space.lg, bottom: 4),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$name  ', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              TextSpan(text: use, style: t.bodyMedium),
            ])),
          ),
        const SizedBox(height: Space.sm),
      ],
    ]);
  }
}

class _Phonetic extends StatelessWidget {
  const _Phonetic();

  static const words = [
    'Alpha', 'Bravo', 'Charlie', 'Delta', 'Echo', 'Foxtrot', 'Golf', 'Hotel', 'India', 'Juliett', 'Kilo', 'Lima', 'Mike',
    'November', 'Oscar', 'Papa', 'Quebec', 'Romeo', 'Sierra', 'Tango', 'Uniform', 'Victor', 'Whisky', 'X-ray', 'Yankee', 'Zulu',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 520 ? 4 : 3;
      final w = (box.maxWidth - (cols - 1) * 6) / cols;
      return Wrap(spacing: 6, runSpacing: 6, children: [
        for (final word in words)
          Container(
            width: w,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(color: c.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.sm)),
            child: Row(children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(6)),
                child: Text(word[0], style: t.labelLarge?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(word, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
            ]),
          ),
      ]);
    });
  }
}

class _Cpr extends StatelessWidget {
  const _Cpr();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    const steps = [
      (Icons.record_voice_over_outlined, 'Check', 'Is the casualty responding? Is the area safe?'),
      (Icons.call_outlined, 'Call for help', 'Shout for help and call an ambulance (108 / 112).'),
      (Icons.favorite_border, '30 compressions', 'Heel of the hand on the centre of the chest, hard and fast, about 100 a minute.'),
      (Icons.air, '2 breaths', 'Tilt the head, lift the chin, give two breaths.'),
      (Icons.repeat, 'Repeat', '30 : 2 until help arrives or the casualty starts breathing.'),
    ];
    return Column(children: [
      for (final (i, (icon, head, what)) in steps.indexed)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Column(children: [
              CircleAvatar(radius: 18, backgroundColor: i == 2 ? c.error : c.primary, child: Icon(icon, size: 18, color: Colors.white)),
              if (i < steps.length - 1) Expanded(child: Container(width: 2, color: c.outlineVariant)),
            ]),
            const SizedBox(width: Space.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${i + 1}. $head', style: t.titleSmall),
                  Text(what, style: t.bodyMedium),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
