import '../core/services/json_loader.dart';
import '../models/chapter.dart';
import '../models/question.dart';
import '../models/section.dart';

class QuestionRepository {
  List<Chapter>? _chapters;
  List<Question>? _questions;
  List<Section>? _sections;

  Future<List<Chapter>> getChapters() async {
    _chapters ??= await JsonLoader.loadChapters();
    return _chapters!;
  }

  Future<List<Question>> getAllQuestions() async {
    _questions ??= await JsonLoader.loadQuestions();
    return _questions!;
  }

  Future<List<Section>> getAllSections() async {
    _sections ??= await JsonLoader.loadSections();
    return _sections!;
  }

  Future<List<Section>> getSectionsByChapter(int chapterId) async {
    final all = await getAllSections();
    final result = all.where((s) => s.chapterId == chapterId).toList();
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  Future<List<Question>> getQuestionsByChapter(int chapterId) async {
    final all = await getAllQuestions();
    return all.where((q) => q.chapterId == chapterId).toList();
  }

  Future<List<Question>> getQuestionsByIds(List<int> ids) async {
    final all = await getAllQuestions();
    final idSet = ids.toSet();
    return all.where((q) => idSet.contains(q.id)).toList();
  }

  Future<List<Question>> getRandomQuestions(int count, {int? chapterId}) async {
    final all = await getAllQuestions();
    final pool = chapterId != null
        ? all.where((q) => q.chapterId == chapterId).toList()
        : all;
    pool.shuffle();
    return pool.take(count).toList();
  }

  /// 依科目隨機抽題
  /// courseId 1 = 保險實務 (chapterId 101-107)
  /// courseId 2 = 保險法規 (chapterId 201-301)
  Future<List<Question>> getRandomQuestionsByCourse(int count, int courseId) async {
    final all = await getAllQuestions();
    final pool = all.where((q) => q.chapterId ~/ 100 == courseId).toList();
    pool.shuffle();
    return pool.take(count).toList();
  }

  /// 錯題優先組題：先將本科目錯題全數納入，再以隨機同科目題目補足 count 題。
  /// 結果打亂順序，確保考生無法從位置判斷哪些是錯題。
  /// wrongIds：當前錯題本中所有題目的 id（不限科目，此處自動篩選）
  Future<List<Question>> getExamQuestionsWithWrongPriority(
    int count,
    int courseId,
    List<int> wrongIds,
  ) async {
    final all = await getAllQuestions();
    final coursePool = all.where((q) => q.chapterId ~/ 100 == courseId).toList();

    final wrongSet = wrongIds.toSet();
    // 本科目的錯題
    final wrongQs = coursePool.where((q) => wrongSet.contains(q.id)).toList();
    // 本科目的非錯題（隨機補位用）
    final randomPool = coursePool.where((q) => !wrongSet.contains(q.id)).toList()
      ..shuffle();

    final result = <Question>[];
    result.addAll(wrongQs.take(count));          // 錯題優先，最多 count 題
    final remaining = count - result.length;
    if (remaining > 0) result.addAll(randomPool.take(remaining)); // 補齊
    result.shuffle();                            // 打亂，隱藏錯題位置
    return result;
  }
}
