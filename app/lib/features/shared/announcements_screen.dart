import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../../data/unit_repository.dart';
import 'widgets.dart';

/// Unit announcements. Cadets read them; admins can post.
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key, required this.editable});

  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = [...ref.watch(announcementsProvider)]
      ..sort((a, b) => a.pinned == b.pinned ? b.createdAt.compareTo(a.createdAt) : (a.pinned ? -1 : 1));
    final now = ref.watch(clockProvider)();

    final body = PageBody(children: [
      if (editable)
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: () => showDialog<void>(context: context, builder: (_) => const _ComposeDialog()),
            icon: const Icon(Icons.campaign_outlined),
            label: const Text('Post announcement'),
          ),
        ),
      const SizedBox(height: Space.md),
      if (items.isEmpty)
        const EmptyState(icon: Icons.campaign_outlined, title: 'No announcements yet',
            message: 'Posts from your ANO and senior cadets will appear here.')
      else
        ListCard(children: [for (final a in items) AnnouncementTile(a, now: now)]),
    ]);

    return editable ? body : Scaffold(appBar: AppBar(title: const Text('Announcements')), body: body);
  }
}

class _ComposeDialog extends ConsumerStatefulWidget {
  const _ComposeDialog();

  @override
  ConsumerState<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends ConsumerState<_ComposeDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _pinned = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool _busy = false;

  Future<void> _post() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Add both a title and a message');
      return;
    }
    final me = ref.read(authControllerProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(announcementsProvider.notifier).post(
            title: _title.text.trim(),
            body: _body.text.trim(),
            author: me?.displayName ?? 'Unit',
            pinned: _pinned,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e is UnitDataFailure ? e.message : 'Couldn\'t post. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Post announcement'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _title, autofocus: true, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: Space.md),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: 'Message', errorText: _error),
          ),
          const SizedBox(height: Space.sm),
          CheckboxListTile(
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v ?? false),
            title: const Text('Pin to the top'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _post, child: const Text('Post announcement')),
      ],
    );
  }
}
