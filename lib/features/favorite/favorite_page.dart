import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/user_data_provider.dart';
import '../../providers/question_provider.dart';

class FavoritePage extends ConsumerWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favIdsAsync = ref.watch(favoriteIdsProvider);
    final allQsAsync = ref.watch(allQuestionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('收藏題目')),
      body: favIdsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗: $e')),
        data: (favIds) {
          if (favIds.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: Colors.amber),
                  SizedBox(height: 16),
                  Text('尚未收藏任何題目', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('在答題時點擊書籤圖示即可收藏', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          final allQs = allQsAsync.valueOrNull ?? [];
          final favQs = allQs.where((q) => favIds.contains(q.id)).toList();

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.amber),
                    const SizedBox(width: 8),
                    Text('已收藏 ${favIds.length} 題'),
                    const Spacer(),
                    ElevatedButton(
                      onPressed: () => context.push('/quiz/0?fav=true'),
                      child: const Text('開始練習'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: favQs.length,
                  itemBuilder: (_, i) {
                    final q = favQs[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.bookmark, color: Colors.white, size: 18),
                        ),
                        title: Text(
                          q.question.length > 50 ? '${q.question.substring(0, 50)}...' : q.question,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text('第 ${q.chapterId % 100} 章 / 第 ${q.questionNo} 題',
                            style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.bookmark_remove, size: 20, color: Colors.amber),
                          onPressed: () async {
                            await ref.read(userDataRepositoryProvider).toggleFavorite(q.id);
                            ref.invalidate(favoriteIdsProvider);
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
}
