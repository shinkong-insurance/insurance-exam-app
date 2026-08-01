import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/question_provider.dart';
import '../../providers/user_data_provider.dart';

class ProgressPage extends ConsumerWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chaptersProvider);
    final allQsAsync = ref.watch(allQuestionsProvider);
    final progressAsync = ref.watch(progressProvider);
    final examRecordsAsync = ref.watch(examRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('學習進度')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Exam records
          const Text('模擬考紀錄', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          examRecordsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox.shrink(),
            data: (records) {
              if (records.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('尚無模擬考紀錄', textAlign: TextAlign.center),
                  ),
                );
              }
              return Column(
                children: records.take(5).map((r) {
                  final pass = r.score >= 70;
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: pass ? Colors.green : Colors.red,
                        child: Text('${r.score}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ),
                      title: Text(r.examName, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '正確 ${r.correctCount}/${r.totalQuestion} | ${r.createTime.substring(0, 16)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Chip(
                        label: Text(pass ? '通過' : '未通過',
                            style: const TextStyle(fontSize: 12)),
                        backgroundColor: pass ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
          // Chapter progress
          const Text('章節答題進度', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          chaptersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('載入失敗: $e'),
            data: (chapters) {
              final allQs = allQsAsync.valueOrNull ?? [];
              final progress = progressAsync.valueOrNull ?? {};

              return Column(
                children: chapters.map((chapter) {
                  final total = allQs.where((q) => q.chapterId == chapter.id).length;
                  final prog = progress[chapter.id];
                  final answered = prog?['answered'] ?? 0;
                  final correct = prog?['correct'] ?? 0;
                  final pct = total > 0 ? answered / total : 0.0;
                  final accuracy = answered > 0 ? correct / answered : 0.0;

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(chapter.title,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Text('$answered/$total 題',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 8,
                              backgroundColor: Colors.grey.withOpacity(0.2),
                            ),
                          ),
                          if (answered > 0) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '正確率 ${(accuracy * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accuracy >= 0.7 ? Colors.green : Colors.orange,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                Text('答對 $correct 題', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
