import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../repositories/question_repository.dart';

final questionRepositoryProvider = Provider<QuestionRepository>(
  (_) => QuestionRepository(),
);

final chaptersProvider = FutureProvider<List<Chapter>>((ref) {
  return ref.read(questionRepositoryProvider).getChapters();
});

final allQuestionsProvider = FutureProvider<List<Question>>((ref) {
  return ref.read(questionRepositoryProvider).getAllQuestions();
});

final chapterQuestionsProvider =
    FutureProvider.family<List<Question>, int>((ref, chapterId) {
  return ref.read(questionRepositoryProvider).getQuestionsByChapter(chapterId);
});
