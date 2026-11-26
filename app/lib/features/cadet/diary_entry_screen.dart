import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/diary.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

/// Log a training session. Built to take under a minute: pick a type,
/// add the numbers that matter for it, jot what went well and what to fix.
class DiaryEntryScreen extends ConsumerStatefulWidget {
  const DiaryEntryScreen({super.key});

  @override
  ConsumerState<DiaryEntryScreen> createState() => _DiaryEntryScreenState();
}

class _DiaryEntryScreenState extends ConsumerState<DiaryEntryScreen> {
  SessionType _type = SessionType.shooting;
  ShootingPosition _position = ShootingPosition.prone;
  final _duration = TextEditingController(text: '60');
  final _rifle = TextEditingController(text: '.22 rifle');
  final _distance = TextEditingController(text: '25');
  final _rounds = TextEditingController(text: '5');
  final _score = TextEditingController();
  final _group = TextEditingController();
  final _wentWell = TextEditingController();
  final _toImprove = TextEditingController();
  final _instructor = TextEditingController();
  double _mood = 3;
  double _fatigue = 3;
  double _sleep = 7;
  bool _share = false;

  @override
  void dispose() {
    for (final c in [_duration, _rifle, _distance, _rounds, _score, _group, _wentWell, _toImprove, _instructor]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    final entry = DiaryEntry(
      id: 'd${DateTime.now().microsecondsSinceEpoch}',
      type: _type,
      date: ref.read(clockProvider)(),
      durationMinutes: int.tryParse(_duration.text),
      wentWell: _text(_wentWell),
      toImprove: _text(_toImprove),
      instructorNotes: _text(_instructor),
      mood: _mood.round(),
      fatigue: _fatigue.round(),
      sleepHours: _sleep,
      sharedWithUnit: _share,
      shooting: _type == SessionType.shooting
          ? ShootingMetrics(
              rifle: _text(_rifle) ?? 'Rifle',
              position: _position,
              distanceMetres: int.tryParse(_distance.text) ?? 0,
              rounds: int.tryParse(_rounds.text) ?? 0,
              score: int.tryParse(_score.text),
              groupMm: double.tryParse(_group.text),
            )
          : null,
    );
    ref.read(diaryProvider.notifier).add(entry);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session logged')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.md);
    Widget number(TextEditingController c, String label, {String? suffix}) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label, suffixText: suffix),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Log session')),
      body: PageBody(children: [
        Text('Session type', style: t.titleSmall),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final s in SessionType.values)
            ChoiceChip(
              avatar: Icon(s.icon, size: 18),
              label: Text(s.label),
              selected: _type == s,
              onSelected: (_) => setState(() => _type = s),
            ),
        ]),
        const SizedBox(height: Space.xl),
        Row(children: [number(_duration, 'Duration', suffix: 'min')]),
        if (_type == SessionType.shooting) ...[
          const SectionHeader('Shooting'),
          TextField(controller: _rifle, decoration: const InputDecoration(labelText: 'Rifle')),
          gap,
          SegmentedButton<ShootingPosition>(
            segments: [
              for (final p in ShootingPosition.values) ButtonSegment(value: p, label: Text(p.label)),
            ],
            selected: {_position},
            onSelectionChanged: (s) => setState(() => _position = s.first),
          ),
          gap,
          Row(children: [
            number(_distance, 'Distance', suffix: 'm'),
            const SizedBox(width: Space.md),
            number(_rounds, 'Rounds'),
          ]),
          gap,
          Row(children: [
            number(_score, 'Score'),
            const SizedBox(width: Space.md),
            number(_group, 'Group size', suffix: 'mm'),
          ]),
          const SizedBox(height: Space.xs),
          Text('Target photo upload and automatic group measurement come in a later phase.',
              style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
        const SectionHeader('Reflection'),
        TextField(
            controller: _wentWell, maxLines: 2,
            decoration: const InputDecoration(labelText: 'What went well')),
        gap,
        TextField(
            controller: _toImprove, maxLines: 2,
            decoration: const InputDecoration(labelText: 'What to improve')),
        gap,
        TextField(
            controller: _instructor, maxLines: 2,
            decoration: const InputDecoration(labelText: 'Instructor corrections')),
        const SectionHeader('How you felt'),
        _LabeledSlider(label: 'Mood', value: _mood, min: 1, max: 5, divisions: 4,
            onChanged: (v) => setState(() => _mood = v)),
        _LabeledSlider(label: 'Fatigue', value: _fatigue, min: 1, max: 5, divisions: 4,
            onChanged: (v) => setState(() => _fatigue = v)),
        _LabeledSlider(label: 'Sleep last night', value: _sleep, min: 3, max: 10, divisions: 14, unit: 'h',
            onChanged: (v) => setState(() => _sleep = v)),
        const SizedBox(height: Space.sm),
        Card(
          child: SwitchListTile(
            value: _share,
            onChanged: (v) => setState(() => _share = v),
            title: const Text('Share with my unit'),
            subtitle: const Text('Off by default. Your ANO sees only entries you share.'),
          ),
        ),
        const SizedBox(height: Space.xl),
        FilledButton(onPressed: _save, child: const Text('Save session')),
      ]),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.unit = '',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return Row(children: [
      SizedBox(width: 128, child: Text(label)),
      Expanded(
        child: Slider(
          value: value, min: min, max: max, divisions: divisions,
          label: '$shown$unit', onChanged: onChanged,
        ),
      ),
      SizedBox(width: 40, child: Text('$shown$unit', textAlign: TextAlign.end)),
    ]);
  }
}
