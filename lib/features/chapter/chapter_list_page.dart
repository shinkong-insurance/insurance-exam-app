import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/question_provider.dart';
import '../../providers/section_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../models/chapter.dart';

class ChapterListPage extends ConsumerWidget {
  const ChapterListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider);
    final allQsAsync = ref.watch(allQuestionsProvider);
    final allSecAsync = ref.watch(allSectionsProvider);
    final progressAsync = ref.watch(progressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('章節學習'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: _TabHint(),
        ),
      ),
      body: chaptersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗: $e')),
        data: (chapters) {
          final allQs = allQsAsync.valueOrNull ?? [];
          final allSecs = allSecAsync.valueOrNull ?? [];
          final progress = progressAsync.valueOrNull ?? {};

          final unit1 = chapters.where((c) => c.unitNo == 1).toList();
          final unit2 = chapters.where((c) => c.unitNo == 2).toList();
          final unit3 = chapters.where((c) => c.unitNo == 3).toList();

          return ListView(
            children: [
              _UnitHeader(
                title: '第一單元：保險實務',
                color: const Color(0xFF1565C0),
              ),
              ..._buildChapterTiles(
                  context, unit1, allQs, allSecs, progress,
                  const Color(0xFF1565C0)),
              _UnitHeader(
                title: '第二單元：保險法規',
                color: const Color(0xFF2E7D32),
              ),
              ..._buildChapterTiles(
                  context, unit2, allQs, allSecs, progress,
                  const Color(0xFF2E7D32)),
              if (unit3.isNotEmpty) ...[
                _UnitHeader(
                  title: '附錄',
                  color: const Color(0xFF6A1B9A),
                ),
                ..._buildChapterTiles(
                    context, unit3, allQs, allSecs, progress,
                    const Color(0xFF6A1B9A)),
              ],
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildChapterTiles(
    BuildContext context,
    List<Chapter> chapters,
    List allQs,
    List allSecs,
    Map<int, Map<String, int>> progress,
    Color color,
  ) {
    return chapters.map((chapter) {
      final qCount = allQs.where((q) => q.chapterId == chapter.id).length;
      final secCount = allSecs.where((s) => s.chapterId == chapter.id).length;
      final prog = progress[chapter.id];
      final answered = prog?['answered'] ?? 0;
      final correct = prog?['correct'] ?? 0;
      final pct = qCount > 0 ? answered / qCount : 0.0;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/chapter/${chapter.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: color.withOpacity(0.15),
                      child: Text(
                        '${chapter.id % 100}',
                        style: TextStyle(
                          fontSize: 13,
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
                          Text(chapter.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _Chip(
                                icon: Icons.menu_book,
                                label: '$secCount 節',
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              _Chip(
                                icon: Icons.quiz,
                                label: '$qCount 題',
                                color: Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              _Chip(
                                icon: Icons.bar_chart,
                                label: chapter.weight,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey[400]),
                  ],
                ),
                if (answered > 0) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 6,
                            backgroundColor: color.withOpacity(0.1),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$correct/$qCount 正確',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _TabHint extends StatelessWidget {
  const _TabHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(
        '點擊章節可查看教材與練習題',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
    );
  }
}

class _UnitHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _UnitHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
