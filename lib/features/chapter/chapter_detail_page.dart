import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/chapter.dart';
import '../../models/section.dart';
import '../../providers/section_provider.dart';
import '../../providers/question_provider.dart';

// ── Main page ────────────────────────────────────────────────────────────────

class ChapterDetailPage extends ConsumerWidget {
  final int chapterId;

  const ChapterDetailPage({super.key, required this.chapterId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sectionsAsync = ref.watch(chapterSectionsProvider(chapterId));
    final chaptersAsync = ref.watch(chaptersProvider);
    final allQsAsync = ref.watch(allQuestionsProvider);

    final chapter = chaptersAsync.valueOrNull
        ?.firstWhere((c) => c.id == chapterId, orElse: () => Chapter(
              id: chapterId,
              courseId: 1,
              unitNo: 1,
              title: '章節內容',
              weight: '',
            ));

    final qCount = allQsAsync.valueOrNull
            ?.where((q) => q.chapterId == chapterId)
            .length ??
        0;

    return Scaffold(
      body: sectionsAsync.when(
        loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator())),
        error: (e, _) =>
            Scaffold(body: Center(child: Text('載入失敗: $e'))),
        data: (sections) => _Body(
          chapterId: chapterId,
          chapter: chapter,
          sections: sections,
          qCount: qCount,
        ),
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final int chapterId;
  final Chapter? chapter;
  final List<Section> sections;
  final int qCount;

  const _Body({
    required this.chapterId,
    required this.chapter,
    required this.sections,
    required this.qCount,
  });

  @override
  Widget build(BuildContext context) {
    final color = _unitColor(chapter?.unitNo ?? 1);

    return CustomScrollView(
      slivers: [
        // ── App bar ──────────────────────────────────────────────────────────
        SliverAppBar(
          expandedHeight: 140,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(
              chapter?.title ?? '章節',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.7)],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '考試比重 ${chapter?.weight ?? ""}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Quick action buttons ──────────────────────────────────
                _ActionButton(
                  icon: Icons.menu_book,
                  label: '閱讀教材',
                  subtitle: '${sections.length} 個小節',
                  color: color,
                  onTap: sections.isNotEmpty
                      ? () => context.push(
                          '/section/${sections.first.chapterId}/${sections.first.id}')
                      : null,
                ),

                const SizedBox(height: 28),

                // ── Sections list ─────────────────────────────────────────
                if (sections.isNotEmpty) ...[
                  _SectionHeader(
                    icon: Icons.list_alt,
                    title: '教材章節',
                    subtitle: '${sections.length} 節',
                    color: color,
                  ),
                  const SizedBox(height: 8),
                  ...sections.asMap().entries.map(
                        (e) => _SectionTile(
                          section: e.value,
                          index: e.key,
                          color: color,
                        ),
                      ),
                  // ── 章節練習卡（緊接最後一節下方）────────────────────
                  if (qCount > 0) _QuizTile(
                    chapterId: chapterId,
                    qCount: qCount,
                  ),
                ] else ...[
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(Icons.article_outlined,
                              size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 12),
                          const Text('本章節教材整理中',
                              style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _unitColor(int unitNo) {
    switch (unitNo) {
      case 1:
        return const Color(0xFF1565C0);
      case 2:
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF6A1B9A);
    }
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: color),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null
          ? color.withOpacity(0.1)
          : Colors.grey.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: onTap != null ? color : Colors.grey, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: onTap != null ? color : Colors.grey,
                  fontSize: 14,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: (onTap != null ? color : Colors.grey).withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTile extends StatelessWidget {
  final Section section;
  final int index;
  final Color color;

  const _SectionTile({
    required this.section,
    required this.index,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final wordCount = section.content.replaceAll(RegExp(r'\s'), '').length;
    final readMinutes = (wordCount / 200).ceil();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(
            '/section/${section.chapterId}/${section.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withOpacity(0.15),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      section.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w500, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '約 $readMinutes 分鐘閱讀  ·  $wordCount 字',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chapter quiz tile ─────────────────────────────────────────────────────

class _QuizTile extends StatelessWidget {
  final int chapterId;
  final int qCount;

  const _QuizTile({required this.chapterId, required this.qCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/quiz/$chapterId'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.orange.withOpacity(0.2),
                child: const Icon(Icons.quiz_outlined,
                    size: 18, color: Colors.orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '本章節練習',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 $qCount 題，測試本章學習成果',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.orange),
            ],
          ),
        ),
      ),
    );
  }
}
