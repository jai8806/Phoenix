import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/figure.dart';
import '../../data/providers.dart';

/// A horizontal strip of précis figures; tap one to open it full screen.
class FigureStrip extends ConsumerStatefulWidget {
  const FigureStrip({super.key, required this.figures, this.height = 120});

  final List<PrecisFigure> figures;
  final double height;

  @override
  ConsumerState<FigureStrip> createState() => _FigureStripState();
}

class _FigureStripState extends ConsumerState<FigureStrip> {
  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(covariant FigureStrip old) {
    super.didUpdateWidget(old);
    if (old.figures != widget.figures) _request();
  }

  void _request() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(figureUrlsProvider.notifier).ensure([for (final f in widget.figures) f.path]);
      });

  @override
  Widget build(BuildContext context) {
    final urls = ref.watch(figureUrlsProvider);
    // Only pictures that are actually on the unit's storage: no empty boxes
    // while the ANO hasn't uploaded them.
    final shown = [for (final f in widget.figures) if (urls[f.path] != null) f];
    if (shown.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: shown.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final f = shown[i];
          return Semantics(
            button: true,
            label: 'Figure from ${f.chapterCode}, page ${f.page ?? ''}',
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => FigureViewer(figures: shown, initial: i),
                fullscreenDialog: true,
              )),
              child: AspectRatio(
                aspectRatio: f.aspect.clamp(0.6, 2.2),
                child: _FigureImage(url: urls[f.path]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FigureImage extends StatelessWidget {
  const _FigureImage({required this.url, this.fit = BoxFit.cover});

  final String? url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
          color: c.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(icon, color: c.onSurfaceVariant),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: url == null
          ? placeholder(Icons.image_outlined)
          : Image.network(
              url!,
              fit: fit,
              loadingBuilder: (_, child, progress) => progress == null ? child : placeholder(Icons.hourglass_empty),
              errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
            ),
    );
  }
}

/// Full-screen figures with pinch-to-zoom, swiping between them.
class FigureViewer extends ConsumerStatefulWidget {
  const FigureViewer({super.key, required this.figures, required this.initial});

  final List<PrecisFigure> figures;
  final int initial;

  @override
  ConsumerState<FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends ConsumerState<FigureViewer> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urls = ref.watch(figureUrlsProvider);
    final f = widget.figures[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${f.chapterCode}${f.page != null ? ' · p. ${f.page}' : ''}'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: Space.lg),
              child: Text('${_index + 1} / ${widget.figures.length}', style: const TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.figures.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: _FigureImage(url: urls[widget.figures[i].path], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}
