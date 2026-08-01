class ExamRecord {
  final int? id;
  final String examName;
  final int score;
  final int totalQuestion;
  final int correctCount;
  final String wrongIds;
  final String createTime;

  const ExamRecord({
    this.id,
    required this.examName,
    required this.score,
    required this.totalQuestion,
    required this.correctCount,
    required this.wrongIds,
    required this.createTime,
  });

  factory ExamRecord.fromMap(Map<String, dynamic> m) => ExamRecord(
    id: m['id'],
    examName: m['exam_name'],
    score: m['score'],
    totalQuestion: m['total_question'],
    correctCount: m['correct_count'],
    wrongIds: m['wrong_ids'] ?? '',
    createTime: m['create_time'],
  );

  Map<String, dynamic> toMap() => {
    'exam_name': examName,
    'score': score,
    'total_question': totalQuestion,
    'correct_count': correctCount,
    'wrong_ids': wrongIds,
    'create_time': createTime,
  };
}
