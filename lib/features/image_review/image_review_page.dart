import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/chapter.dart';
import '../../models/section.dart';
import '../../providers/question_provider.dart';
import '../../providers/section_provider.dart';

class ImageReviewPage extends ConsumerStatefulWidget {
  const ImageReviewPage({super.key});

  @override
  ConsumerState<ImageReviewPage> createState() => _ImageReviewPageState();
}

class _ImageReviewPageState extends ConsumerState<ImageReviewPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int? _selectedChapter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('圖片複習'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.star_outline), text: '重點標記'),
            Tab(icon: Icon(Icons.account_tree), text: '章節架構'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _KeyPointsTab(
            selectedChapter: _selectedChapter,
            onChapterSelected: (id) => setState(() => _selectedChapter = id),
          ),
          const _StructureTab(),
        ],
      ),
    );
  }
}

// ─── Tab 1: Key Points ────────────────────────────────────────────────────────

class _KeyPointsTab extends ConsumerWidget {
  final int? selectedChapter;
  final ValueChanged<int?> onChapterSelected;

  const _KeyPointsTab({
    required this.selectedChapter,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider);
    final allSectionsAsync = ref.watch(allSectionsProvider);

    final chapters = chaptersAsync.valueOrNull ?? <Chapter>[];
    final allSections = allSectionsAsync.valueOrNull ?? <Section>[];

    final filteredSections = selectedChapter == null
        ? allSections
        : allSections.where((s) => s.chapterId == selectedChapter).toList();

    // Extract ※ / note lines from sections
    final keyPoints = <_KeyPoint>[];
    for (final sec in filteredSections) {
      final chap = chapters.cast<Chapter?>().firstWhere(
            (c) => c?.id == sec.chapterId,
            orElse: () => null,
          );
      if (chap == null) continue;
      final lines = sec.content.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('※') ||
            trimmed.startsWith('▲') ||
            trimmed.contains('重點') ||
            trimmed.contains('注意') ||
            trimmed.contains('考點')) {
          keyPoints.add(_KeyPoint(
            content: trimmed,
            sectionTitle: sec.title,
            chapterTitle: chap.title,
            chapterId: sec.chapterId,
            sectionId: sec.id,
          ));
        }
      }
    }

    return Column(
      children: [
        // Chapter filter chips
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              FilterChip(
                label: const Text('全部'),
                selected: selectedChapter == null,
                onSelected: (_) => onChapterSelected(null),
              ),
              ...chapters.map((c) => Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: FilterChip(
                      label: Text('第${c.id % 100}章'),
                      selected: selectedChapter == c.id,
                      onSelected: (_) => onChapterSelected(
                          selectedChapter == c.id ? null : c.id),
                    ),
                  )),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Icon(Icons.star, size: 14, color: Colors.amber[700]),
              const SizedBox(width: 4),
              Text(
                '找到 ${keyPoints.length} 個重點標記',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        Expanded(
          child: keyPoints.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('此章節無特別標記重點',
                          style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: keyPoints.length,
                  itemBuilder: (context, i) =>
                      _KeyPointCard(point: keyPoints[i]),
                ),
        ),
      ],
    );
  }
}

class _KeyPoint {
  final String content;
  final String sectionTitle;
  final String chapterTitle;
  final int chapterId;
  final int sectionId;

  const _KeyPoint({
    required this.content,
    required this.sectionTitle,
    required this.chapterTitle,
    required this.chapterId,
    required this.sectionId,
  });
}

class _KeyPointCard extends StatelessWidget {
  final _KeyPoint point;
  const _KeyPointCard({required this.point});

  Color get _accentColor {
    if (point.content.startsWith('※')) return Colors.orange;
    if (point.content.startsWith('▲')) return Colors.red;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final color = _accentColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.push('/section/${point.chapterId}/${point.sectionId}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: color.withOpacity(0.4)),
                    ),
                    child: Text(
                      point.sectionTitle,
                      style: TextStyle(
                          fontSize: 11,
                          color: color,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  Text(point.chapterTitle,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.grey)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios,
                      size: 11, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                point.content,
                style: const TextStyle(fontSize: 13.5, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Tab 2: Structure Overview ────────────────────────────────────────────────

class _StructureTab extends ConsumerWidget {
  const _StructureTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider);
    final allSectionsAsync = ref.watch(allSectionsProvider);

    final chapters = chaptersAsync.valueOrNull ?? <Chapter>[];
    final allSections = allSectionsAsync.valueOrNull ?? <Section>[];

    final unit1 = chapters.where((c) => c.unitNo == 1).toList();
    final unit2 = chapters.where((c) => c.unitNo == 2).toList();

    if (chapters.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _StructureUnit(
          title: '第一單元：保險實務',
          color: const Color(0xFF1565C0),
          chapters: unit1,
          allSections: allSections,
        ),
        const SizedBox(height: 16),
        _StructureUnit(
          title: '第二單元：保險法規',
          color: const Color(0xFF2E7D32),
          chapters: unit2,
          allSections: allSections,
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _StructureUnit extends StatelessWidget {
  final String title;
  final Color color;
  final List<Chapter> chapters;
  final List<Section> allSections;

  const _StructureUnit({
    required this.title,
    required this.color,
    required this.chapters,
    required this.allSections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.layers, color: color, size: 18),
                const SizedBox(width: 8),
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 13)),
                const Spacer(),
                Text('${chapters.length} 章',
                    style: TextStyle(
                        fontSize: 12, color: color.withOpacity(0.7))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: chapters
                  .map((chap) => _ChapterNode(
                        chapter: chap,
                        sections: allSections
                            .where((s) => s.chapterId == chap.id)
                            .toList(),
                        color: color,
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterNode extends StatefulWidget {
  final Chapter chapter;
  final List<Section> sections;
  final Color color;

  const _ChapterNode({
    required this.chapter,
    required this.sections,
    required this.color,
  });

  @override
  State<_ChapterNode> createState() => _ChapterNodeState();
}

class _ChapterNodeState extends State<_ChapterNode> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 18,
                  color: widget.color,
                ),
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '第${widget.chapter.id % 100}章',
                    style: TextStyle(
                        fontSize: 11,
                        color: widget.color,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.chapter.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                Text(
                  '${widget.chapter.weight} · ${widget.sections.length}節',
                  style: TextStyle(
                      fontSize: 11, color: widget.color.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 26, bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.sections.map((sec) {
                return GestureDetector(
                  onTap: () =>
                      context.push('/section/${sec.chapterId}/${sec.id}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: widget.color.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(sec.title,
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 10, color: Colors.grey[400]),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        Divider(height: 1, color: widget.color.withOpacity(0.1)),
      ],
    );
  }
}
