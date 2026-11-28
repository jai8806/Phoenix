import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/user.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

/// The cadet's own details. Role and unit stay with the ANO.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final AppUser _start = ref.read(authControllerProvider)!;
  late final _name = TextEditingController(text: _start.fullName);
  late final _regNo = TextEditingController(text: _start.regimentalNo ?? '');
  late String? _rank = _start.rank;
  late Wing? _wing = _start.wing;
  late Division? _division = _start.division;
  late int? _year = _start.trainingYear;
  String? _nameError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _regNo.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) return setState(() => _nameError = 'Enter your name as it appears on your NCC records.');
    setState(() {
      _saving = true;
      _error = null;
    });
    final regNo = _regNo.text.trim().toUpperCase();
    try {
      await ref.read(authControllerProvider.notifier).updateProfile(_start.copyWith(
            fullName: name,
            rank: () => _rank,
            regimentalNo: () => regNo.isEmpty ? null : regNo,
            wing: () => _wing,
            division: () => _division,
            trainingYear: () => _year,
          ));
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;
    final ranks = {...cadetRanks, if (_start.rank != null) _start.rank!}.toList();
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
          child: Text(s, style: t.labelLarge),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: PageBody(children: [
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() => _nameError = null),
          decoration: InputDecoration(labelText: 'Full name', errorText: _nameError),
        ),
        const SizedBox(height: Space.lg),
        TextField(
          controller: _regNo,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Regimental number', hintText: 'e.g. KA2024SDA0123456'),
        ),
        label('Rank'),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          for (final r in ranks)
            ChoiceChip(
              label: Text(r),
              selected: _rank == r,
              onSelected: (on) => setState(() => _rank = on ? r : null),
            ),
        ]),
        label('Wing'),
        SegmentedButton<Wing>(
          emptySelectionAllowed: true,
          segments: [
            for (final w in [Wing.army, Wing.navy, Wing.air]) ButtonSegment(value: w, label: Text(w.label)),
          ],
          selected: {?_wing},
          onSelectionChanged: (s) => setState(() => _wing = s.isEmpty ? null : s.first),
        ),
        label('Division'),
        SegmentedButton<Division>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: Division.sd, label: Text('SD')),
            ButtonSegment(value: Division.sw, label: Text('SW')),
            ButtonSegment(value: Division.jd, label: Text('JD')),
            ButtonSegment(value: Division.jw, label: Text('JW')),
          ],
          selected: {?_division},
          onSelectionChanged: (s) => setState(() => _division = s.isEmpty ? null : s.first),
        ),
        label('Training year'),
        SegmentedButton<int>(
          emptySelectionAllowed: true,
          segments: const [
            ButtonSegment(value: 1, label: Text('1st year')),
            ButtonSegment(value: 2, label: Text('2nd year')),
            ButtonSegment(value: 3, label: Text('3rd year')),
          ],
          selected: {?_year},
          onSelectionChanged: (s) => setState(() => _year = s.isEmpty ? null : s.first),
        ),
        const SizedBox(height: Space.sm),
        Text('Your wing and division pick the right study material. Your ANO changes roles.',
            style: t.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        if (_error != null) ...[
          const SizedBox(height: Space.lg),
          Text(_error!, style: t.bodyMedium?.copyWith(color: c.error)),
        ],
        const SizedBox(height: Space.xl),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save profile')),
      ]),
    );
  }
}
