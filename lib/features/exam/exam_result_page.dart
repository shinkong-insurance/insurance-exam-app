import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/question.dart';

class ExamResultPage extends StatelessWidget {
  final Map<String, dynamic> result;
  const ExamResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final score = result['score'] as int;
    final correct = result['correct'] as int;
    final total = result['total'] as int;
    final questions = result['questions'] as List<Question>;
    final answers = result['answers'] as Map<int, int>;
    final pass = score >= 70;

    return Scaffold(
      appBar: AppBar(
        title: const Text('考試結果'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        children: [
          // Score card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: pass
                    ? [Colors.green.shade700, Colors.green.shade400]
                    : [Colors.red.shade700, Colors.red.shade400],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(pass ? '恭喜通過！' : '繼續加油！',
                    style: const TextStyle(color: Colors.white, fontSize: 20,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text('$score 分',
                    style: const TextStyle(color: Colors.white, fontSize: 56,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('答對 $correct / $total 題  |  及格分數 70分',
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.home),
                    label: const Text('返回首頁'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/wrongbook'),
                    icon: const Icon(Icons.error_outline),
                    label: const Text('查看錯題'),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('答題明細', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...List.generate(questions.length, (i) {
            final q = questions[i];
            final ans = answers[i];
            final isCorrect = ans == q.answer;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ExpansionTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: isCorrect ? Colors.green : Colors.red,
                  child: Icon(
                    isCorrect ? Icons.check : Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                title: Text('第${i + 1}題', style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  q.question.length > 40 ? '${q.question.substring(0, 40)}...' : q.question,
                  style: const TextStyle(fontSize: 12),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q.question, style: const TextStyle(height: 1.5)),
                        const SizedBox(height: 8),
                        ...List.generate(4, (j) {
                          final opt = j + 1;
                          Color? color;
                          if (opt == q.answer) color = Colors.green;
                          if (opt == ans && ans != q.answer) color = Colors.red;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Text('(${j + 1}) ',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: color != null ? FontWeight.bold : null,
                                    )),
                                Expanded(
                                  child: Text(q.options[j],
                                      style: TextStyle(
                                        color: color,
                                        fontWeight: color != null ? FontWeight.bold : null,
                                      )),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (ans == null)
                          const Text('（未作答）', style: TextStyle(color: Colors.orange)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
