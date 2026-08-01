import 'dart:async';
import '../core/database/shared_preferences_store.dart';
import '../core/services/cloud_sync_service.dart';
import '../models/wrong_book.dart';
import '../models/exam_record.dart';

class UserDataRepository {
  final _store = SharedPreferencesStore.instance;

  // ── Wrong Book ──────────────────────────────────────────────

  Future<List<int>> getWrongQuestionIds() async {
    final data = await _store.getWrongBook();
    return data.keys.map(int.parse).toList();
  }

  Future<List<WrongBook>> getWrongBooks() async {
    final data = await _store.getWrongBook();
    return data.values
        .map((v) => WrongBook.fromMap(v as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.lastWrongTime.compareTo(a.lastWrongTime));
  }

  Future<void> addWrong(int questionId) async {
    await _store.addWrong(questionId);
    // LK 模式：同步到 Supabase（不等待，不影響 UI）
    unawaited(CloudSyncService.recordWrong(questionId.toString()));
  }

  Future<void> removeWrong(int questionId) async {
    await _store.removeWrong(questionId);
    unawaited(CloudSyncService.removeWrong(questionId.toString()));
  }

  Future<void> clearWrongBook() async {
    await _store.clearWrongBook();
    unawaited(CloudSyncService.clearAllWrong());
  }

  // ── Favorite ────────────────────────────────────────────────

  Future<List<int>> getFavoriteIds() => _store.getFavoriteIds();
  Future<bool> isFavorite(int questionId) => _store.isFavorite(questionId);

  Future<void> toggleFavorite(int questionId) async {
    final wasFav = await _store.isFavorite(questionId);
    await _store.toggleFavorite(questionId);
    // LK 模式：同步到 Supabase
    if (wasFav) {
      unawaited(CloudSyncService.removeFavorite(questionId.toString()));
    } else {
      unawaited(CloudSyncService.addFavorite(questionId.toString()));
    }
  }

  // ── Study Progress ──────────────────────────────────────────

  Future<Map<int, Map<String, int>>> getProgress() => _store.getProgress();

  Future<void> updateProgress(
          int chapterId, int answered, int correct) =>
      _store.updateProgress(chapterId, answered, correct);

  // ── Exam Record ─────────────────────────────────────────────

  Future<List<ExamRecord>> getExamRecords() async {
    final raw = await _store.getExamRecordsRaw();
    return raw
        .asMap()
        .entries
        .map((e) => ExamRecord.fromMap({...e.value, 'id': e.key}))
        .toList();
  }

  Future<void> saveExamRecord(ExamRecord record) =>
      _store.saveExamRecord(record.toMap());
}
