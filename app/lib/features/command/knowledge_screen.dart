import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/providers.dart';
import '../shared/widgets.dart';

/// Where the ANO manages the material Ustaad answers from.
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);
    final t = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    return PageBody(children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How Ustaad learns', style: t.titleMedium),
            const SizedBox(height: Space.sm),
            Text(
              'Upload precis, notes or circulars. Phoenix splits them into passages, indexes them, and Ustaad '
              'answers only from these passages, showing the document and page for every answer.',
              style: t.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: Space.md),
            Tooltip(
              message: 'Uploads open in Phase 1, once the ingestion service is live',
              child: FilledButton.icon(onPressed: null, icon: const Icon(Icons.upload), label: const Text('Upload document')),
            ),
          ]),
        ),
      ),
      const SectionHeader('Official syllabus'),
      ListCard(children: [
        for (final d in docs)
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(d.title),
            subtitle: Text(d.scope),
            trailing: Chip(label: Text(d.status.label)),
          ),
      ]),
    ]);
  }
}
