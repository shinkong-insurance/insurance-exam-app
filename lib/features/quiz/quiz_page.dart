import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/chapter.dart';
import '../../models/question.dart';
import '../../providers/question_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../repositories/user_data_repository.dart';

class QuizPage extends ConsumerStatefulWidget {
  final int chapterId;
  final bool isWrongBook;
  final bool isFavorite;

  const QuizPage({
    super.key,
    required this.chapterId,
    this.isWrongBook = false,
    this.isFavorite = false,
  });

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  List<Question> _questions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _showAnswer = false;
  bool _isFav = false;
  bool _loading = true;
  int _correctCount = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final repo = ref.read(questionRepositoryProvider);
    final userRepo = ref.read(userDataRepositoryProvider);
    List<Question> qs;

    if (widget.isWrongBook) {
      final wrongIds = await userRepo.getWrongQuestionIds();
      qs = wrongIds.isEmpty ? [] : await repo.getQuestionsByIds(wrongIds);
    } else if (widget.isFavorite) {
      final favIds = await userRepo.getFavoriteIds();
      qs = favIds.isEmpty ? [] : await repo.getQuestionsByIds(favIds);
    } else {
      qs = await repo.getQuestionsByChapter(widget.chapterId);
    }

    if (mounted) {
      setState(() {
        _questions = qs;
        _loading = false;
      });
      if (qs.isNotEmpty) _checkFav();
    }
  }

  Future<void> _checkFav() async {
    if (_questions.isEmpty) return;
    final fav = await ref.read(userDataRepositoryProvider)
        .isFavorite(_questions[_currentIndex].id);
    if (mounted) setState(() => _isFav = fav);
  }

  Future<void> _submitAnswer(int answer) async {
    if (_showAnswer) return;
    final q = _questions[_currentIndex];
    final isCorrect = answer == q.answer;
    final userRepo = ref.read(userDataRepositoryProvider);

    if (isCorrect) {
      _correctCount++;
    } else {
      await userRepo.addWrong(q.id);
      ref.invalidate(wrongIdsProvider); // 通知首頁更新錯題計數
    }

    setState(() {
      _selectedAnswer = answer;
      _showAnswer = true;
    });
  }

  Future<void> _toggleFav() async {
    final q = _questions[_currentIndex];
    await ref.read(userDataRepositoryProvider).toggleFavorite(q.id);
    ref.invalidate(favoriteIdsProvider);
    final fav = await ref.read(userDataRepositoryProvider).isFavorite(q.id);
    if (mounted) setState(() => _isFav = fav);
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _showAnswer = false;
      });
      _checkFav();
    } else {
      _saveProgressAndFinish();
    }
  }

  void _prevQuestion() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _selectedAnswer = null;
        _showAnswer = false;
      });
      _checkFav();
    }
  }

  Future<void> _saveProgressAndFinish() async {
    if (!widget.isWrongBook && !widget.isFavorite) {
      await ref.read(userDataRepositoryProvider).updateProgress(
        widget.chapterId,
        _questions.length,
        _correctCount,
      );
      ref.invalidate(progressProvider);
    }
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('章節完成！'),
          content: Text('答題完成\n正確：$_correctCount / ${_questions.length}'),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); context.pop(); },
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('題庫練習')),
        body: const Center(child: Text('目前沒有題目')),
      );
    }

    final q = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isWrongBook
                  ? '錯題本'
                  : widget.isFavorite
                      ? '收藏題目'
                      : ref.watch(chaptersProvider).valueOrNull
                              ?.firstWhere(
                                (c) => c.id == widget.chapterId,
                                orElse: () => Chapter(
                                  id: 0, courseId: 1, unitNo: 1,
                                  title: '章節練習', weight: ''),
                              )
                              .title ??
                          '章節練習',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '第 ${_currentIndex + 1} 題 / 共 ${_questions.length} 題',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isFav ? Icons.bookmark : Icons.bookmark_border,
                color: _isFav ? Colors.amber : null),
            onPressed: _toggleFav,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress, minHeight: 4),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question number chip
                  Chip(
                    label: Text('第 ${q.questionNo} 題'),
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  const SizedBox(height: 12),
                  // Question text
                  Text(q.question,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500,
                          height: 1.6)),
                  const SizedBox(height: 20),
                  // Options
                  ...List.generate(4, (i) => _OptionTile(
                    index: i,
                    text: q.options[i],
                    selected: _selectedAnswer == i + 1,
                    isCorrect: q.answer == i + 1,
                    showResult: _showAnswer,
                    onTap: () => _submitAnswer(i + 1),
                  )),
                  // Explanation
                  if (_showAnswer && q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('解析', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Text(q.explanation, style: const TextStyle(height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          // Bottom nav
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _currentIndex > 0 ? _prevQuestion : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('上一題'),
                  ),
                  const Spacer(),
                  if (!_showAnswer)
                    ElevatedButton.icon(
                      onPressed: () => _submitAnswer(0),
                      icon: const Icon(Icons.visibility),
                      label: const Text('顯示答案'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                    ),
                  if (_showAnswer)
                    ElevatedButton.icon(
                      onPressed: _nextQuestion,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_currentIndex < _questions.length - 1 ? '下一題' : '完成'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final int index;
  final String text;
  final bool selected;
  final bool isCorrect;
  final bool showResult;
  final VoidCallback onTap;

  const _OptionTile({
    required this.index,
    required this.text,
    required this.selected,
    required this.isCorrect,
    required this.showResult,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color? bgColor;
    Color? borderColor;

    if (showResult) {
      if (isCorrect) {
        bgColor = Colors.green.withOpacity(0.15);
        borderColor = Colors.green;
      } else if (selected && !isCorrect) {
        bgColor = Colors.red.withOpacity(0.15);
        borderColor = Colors.red;
      }
    } else if (selected) {
      bgColor = Theme.of(context).colorScheme.primaryContainer;
      borderColor = Theme.of(context).colorScheme.primary;
    }

    final labels = ['(1)', '(2)', '(3)', '(4)'];

    return GestureDetector(
      onTap: showResult ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor ?? Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor ?? Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Text(labels[index],
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: borderColor ?? Theme.of(context).colorScheme.primary)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
            if (showResult && isCorrect)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
            if (showResult && selected && !isCorrect)
              const Icon(Icons.cancel, color: Colors.red, size: 20),
          ],
        ),
      ),
    );
  }
}
