import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/user_data_provider.dart';
import '../../providers/question_provider.dart';

class WrongBookPage extends ConsumerWidget {
  const WrongBookPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrongIdsAsync = ref.watch(wrongIdsProvider);
    final allQsAsync = ref.watch(allQuestionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('錯題本'),
        actions: [
          wrongIdsAsync.maybeWhen(
            data: (ids) => ids.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.delete_sweep),
                    tooltip: '清空錯題本',
                    onPressed: () => _confirmClear(context, ref),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: wrongIdsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗: $e')),
        data: (wrongIds) {
          if (wrongIds.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                  SizedBox(height: 16),
                  Text('太棒了！目前沒有錯題', style: TextStyle(fontSize: 18)),
                ],
              ),
            );
          }
          final allQs = allQsAsync.valueOrNull ?? [];
          final wrongQs = allQs.where((q) => wrongIds.contains(q.id)).toList();

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('共 ${wrongIds.length} 題錯題需複習'),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => context.push('/quiz/0?wrong=true'),
                      child: const Text('開始複習'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: wrongQs.length,
                  itemBuilder: (_, i) {
                    final q = wrongQs[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.red,
                          child: Icon(Icons.close, color: Colors.white, size: 18),
                        ),
                        title: Text(
                          q.question.length > 50 ? '${q.question.substring(0, 50)}...' : q.question,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text('第 ${q.chapterId % 100} 章 / 第 ${q.questionNo} 題',
                            style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () async {
                            await ref.read(userDataRepositoryProvider).removeWrong(q.id);
                            ref.invalidate(wrongIdsProvider);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空錯題本'),
        content: const Text('確定要清空所有錯題記錄嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(userDataRepositoryProvider).clearWrongBook();
              ref.invalidate(wrongIdsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('確定清空'),
          ),
        ],
      ),
    );
  }
}
