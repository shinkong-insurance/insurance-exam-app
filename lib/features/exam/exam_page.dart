import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/question.dart';
import '../../providers/question_provider.dart';
import '../../providers/user_data_provider.dart';
import '../../models/exam_record.dart';
import '../../core/services/study_logger.dart';

class ExamPage extends ConsumerStatefulWidget {
  final int count;
  final int? chapterId;
  final int? courseId;    // 1=保險實務, 2=保險法規
  final bool wrongPriority; // 優先納入錯題本中該科目的題目
  final String? paperName;  // 卷別名稱（如「保險實務A卷」），顯示於 AppBar 與記錄

  const ExamPage({
    super.key,
    required this.count,
    this.chapterId,
    this.courseId,
    this.wrongPriority = false,
    this.paperName,
  });

  @override
  ConsumerState<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends ConsumerState<ExamPage> {
  List<Question> _questions = [];
  final Map<int, int> _answers = {}; // index -> chosen answer
  int _currentIndex = 0;
  bool _submitted = false;
  bool _loading = true;
  Set<int> _wrongIdsAtStart = {}; // 考試開始時錯題本中的題目 id（用於答對後移除）

  // ── 計時器（背景運作，不顯示） ──────────────
  Timer? _timer;
  int _secondsLeft = 0;
  bool _warningShown = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadQuestions() async {
    final repo = ref.read(questionRepositoryProvider);
    final userRepo = ref.read(userDataRepositoryProvider);
    List<Question> qs;

    if (widget.wrongPriority && widget.courseId != null) {
      // 取得當前全部錯題 id，並記錄快照（交卷時用來判斷哪些是錯題）
      final wrongIds = await userRepo.getWrongQuestionIds();
      _wrongIdsAtStart = wrongIds.toSet();
      qs = await repo.getExamQuestionsWithWrongPriority(
        widget.count, widget.courseId!, wrongIds,
      );
    } else if (widget.courseId != null) {
      qs = await repo.getRandomQuestionsByCourse(widget.count, widget.courseId!);
    } else {
      qs = await repo.getRandomQuestions(widget.count, chapterId: widget.chapterId);
    }

    if (mounted) {
      setState(() { _questions = qs; _loading = false; });
      _startTimer();
    }
  }

  void _startTimer() {
    // 50題 = 3600秒(60分鐘)，100題 = 4800秒(80分鐘)
    _secondsLeft = widget.count <= 50 ? 3600 : 4800;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) { _timer?.cancel(); return; }
      setState(() => _secondsLeft--);

      // 剩5分鐘警告（只出現一次）
      if (_secondsLeft == 300 && !_warningShown) {
        _warningShown = true;
        _showWarning();
      }

      // 時間到，自動交卷
      if (_secondsLeft <= 0) {
        _timer?.cancel();
        _autoSubmit();
      }
    });
  }

  void _showWarning() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Text('距離結束剩 5 分鐘'),
          ],
        ),
        content: const Text('請盡快完成作答，時間到後系統將自動交卷。'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('繼續作答'),
          ),
        ],
      ),
    );
  }

  void _selectAnswer(int answer) {
    if (_submitted) return;
    setState(() => _answers[_currentIndex] = answer);
  }

  Future<void> _submitExam() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認交卷'),
        content: Text('已作答 ${_answers.length}/${_questions.length} 題，確定交卷？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('繼續作答')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('確認交卷')),
        ],
      ),
    );
    if (confirm != true) return;

    _timer?.cancel();
    setState(() => _submitted = true);
    await _doSubmit();
  }

  Future<void> _autoSubmit() async {
    if (!mounted) return;
    setState(() => _submitted = true);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer_off, color: Colors.red),
            SizedBox(width: 8),
            Text('考試時間結束'),
          ],
        ),
        content: const Text('考試時間已到，系統將自動交卷。'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確認'),
          ),
        ],
      ),
    );

    await _doSubmit();
  }

  Future<void> _doSubmit() async {
    if (!mounted) return;

    int correct = 0;
    final List<int> wrongIds = [];
    final userRepo = ref.read(userDataRepositoryProvider);

    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      final ans = _answers[i];
      if (ans == q.answer) {
        correct++;
        // wrongPriority 模式：答對的錯題自動從錯題本移除
        if (widget.wrongPriority && _wrongIdsAtStart.contains(q.id)) {
          await userRepo.removeWrong(q.id);
        }
      } else {
        wrongIds.add(q.id);
        await userRepo.addWrong(q.id);
      }
    }
    ref.invalidate(wrongIdsProvider);

    final score = (correct / _questions.length * 100).round();
    final subjectTag = widget.courseId == 1 ? '保險實務 ' : widget.courseId == 2 ? '保險法規 ' : '';
    final timeStamp = DateTime.now().toString().substring(0, 16);
    final examName = widget.paperName != null
        ? '${widget.paperName} $timeStamp'
        : '模擬考 $subjectTag${widget.count}題 $timeStamp';
    await userRepo.saveExamRecord(
      ExamRecord(
        examName: examName,
        score: score,
        totalQuestion: _questions.length,
        correctCount: correct,
        wrongIds: wrongIds.join(','),
        createTime: DateTime.now().toIso8601String(),
      ),
    );
    ref.invalidate(examRecordsProvider);

    // 記錄學習事件
    final isMock = widget.paperName != null || widget.count >= 50;
    StudyLogger.quizSession(
      questionsTotal: _questions.length,
      questionsCorrect: correct,
      chapterId: widget.chapterId,
      courseId: widget.courseId,
      isMockExam: isMock,
    );

    if (mounted) {
      context.pushReplacement('/exam-result', extra: {
        'score': score,
        'correct': correct,
        'total': _questions.length,
        'wrongIds': wrongIds,
        'questions': _questions,
        'answers': Map<int, int>.from(_answers),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final q = _questions[_currentIndex];
    final selected = _answers[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.paperName != null
            ? '${widget.paperName}  ${_currentIndex + 1}/${_questions.length}'
            : '模擬考 ${_currentIndex + 1}/${_questions.length}'),
        actions: [
          TextButton(
            onPressed: _submitExam,
            child: const Text('交卷', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentIndex + 1) / _questions.length,
            minHeight: 4,
          ),
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
                  Chip(label: Text('第 ${_currentIndex + 1} 題')),
                  const SizedBox(height: 12),
                  Text(q.question,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, height: 1.6)),
                  const SizedBox(height: 20),
                  ...List.generate(4, (i) {
                    final opt = i + 1;
                    final isSelected = selected == opt;
                    return GestureDetector(
                      onTap: () => _selectAnswer(opt),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text('(${i + 1})',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.primary)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(q.options[i], style: const TextStyle(height: 1.4))),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          // Answer grid shortcut
          Container(
            height: 48,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: _questions.length,
              itemBuilder: (_, i) {
                Color color;
                if (i == _currentIndex) {
                  color = Theme.of(context).colorScheme.primary;
                } else if (_answers.containsKey(i)) {
                  color = Colors.green.shade700;
                } else {
                  color = Colors.grey.shade600;
                }
                return GestureDetector(
                  onTap: () => setState(() => _currentIndex = i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _currentIndex > 0
                        ? () => setState(() => _currentIndex--)
                        : null,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('上一題'),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _currentIndex < _questions.length - 1
                        ? () => setState(() => _currentIndex++)
                        : _submitExam,
                    icon: Icon(_currentIndex < _questions.length - 1
                        ? Icons.arrow_forward
                        : Icons.check),
                    label: Text(_currentIndex < _questions.length - 1 ? '下一題' : '交卷'),
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
