class WrongBook {
  final int? id;
  final int questionId;
  final int wrongCount;
  final String lastWrongTime;

  const WrongBook({
    this.id,
    required this.questionId,
    required this.wrongCount,
    required this.lastWrongTime,
  });

  factory WrongBook.fromMap(Map<String, dynamic> m) => WrongBook(
    id: m['id'],
    questionId: m['question_id'],
    wrongCount: m['wrong_count'],
    lastWrongTime: m['last_wrong_time'],
  );

  Map<String, dynamic> toMap() => {
    'question_id': questionId,
    'wrong_count': wrongCount,
    'last_wrong_time': lastWrongTime,
  };
}
