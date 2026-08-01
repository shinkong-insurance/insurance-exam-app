import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Web-compatible key-value store backed by SharedPreferences.
/// Replaces the SQLite (sqflite) database for cross-platform support.
class SharedPreferencesStore {
  static SharedPreferencesStore? _instance;
  static SharedPreferencesStore get instance =>
      _instance ??= SharedPreferencesStore._();
  SharedPreferencesStore._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Generic helpers ──────────────────────────────────────────

  Future<List<dynamic>> _getList(String key) async {
    final p = await prefs;
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return [];
    return json.decode(raw) as List<dynamic>;
  }

  Future<void> _setList(String key, List<dynamic> list) async {
    final p = await prefs;
    await p.setString(key, json.encode(list));
  }

  Future<Map<String, dynamic>> _getMap(String key) async {
    final p = await prefs;
    final raw = p.getString(key);
    if (raw == null || raw.isEmpty) return {};
    return json.decode(raw) as Map<String, dynamic>;
  }

  Future<void> _setMap(String key, Map<String, dynamic> map) async {
    final p = await prefs;
    await p.setString(key, json.encode(map));
  }

  // ── Wrong Book ───────────────────────────────────────────────
  static const _kWrongBook = 'wrong_book';

  Future<Map<String, dynamic>> getWrongBook() => _getMap(_kWrongBook);

  Future<void> addWrong(int questionId) async {
    final data = await getWrongBook();
    final key = questionId.toString();
    if (data.containsKey(key)) {
      data[key]['wrong_count'] = (data[key]['wrong_count'] as int) + 1;
      data[key]['last_wrong_time'] = DateTime.now().toIso8601String();
    } else {
      data[key] = {
        'question_id': questionId,
        'wrong_count': 1,
        'last_wrong_time': DateTime.now().toIso8601String(),
      };
    }
    await _setMap(_kWrongBook, data);
  }

  Future<void> removeWrong(int questionId) async {
    final data = await getWrongBook();
    data.remove(questionId.toString());
    await _setMap(_kWrongBook, data);
  }

  Future<void> clearWrongBook() async {
    await _setMap(_kWrongBook, {});
  }

  // ── Favorites ────────────────────────────────────────────────
  static const _kFavorites = 'favorites';

  Future<List<int>> getFavoriteIds() async {
    final list = await _getList(_kFavorites);
    return list.map((e) => e as int).toList();
  }

  Future<bool> isFavorite(int questionId) async {
    final list = await getFavoriteIds();
    return list.contains(questionId);
  }

  Future<void> toggleFavorite(int questionId) async {
    final list = await getFavoriteIds();
    if (list.contains(questionId)) {
      list.remove(questionId);
    } else {
      list.add(questionId);
    }
    await _setList(_kFavorites, list);
  }

  // ── Study Progress ───────────────────────────────────────────
  static const _kProgress = 'study_progress';

  Future<Map<String, dynamic>> _getRawProgress() => _getMap(_kProgress);

  Future<Map<int, Map<String, int>>> getProgress() async {
    final raw = await _getRawProgress();
    final result = <int, Map<String, int>>{};
    for (final entry in raw.entries) {
      final chapterId = int.tryParse(entry.key);
      if (chapterId == null) continue;
      final v = entry.value as Map<String, dynamic>;
      result[chapterId] = {
        'answered': v['answered'] as int,
        'correct': v['correct'] as int,
      };
    }
    return result;
  }

  Future<void> updateProgress(
      int chapterId, int answered, int correct) async {
    final raw = await _getRawProgress();
    raw[chapterId.toString()] = {
      'answered': answered,
      'correct': correct,
      'updated_time': DateTime.now().toIso8601String(),
    };
    await _setMap(_kProgress, raw);
  }

  // ── Exam Records ─────────────────────────────────────────────
  static const _kExamRecords = 'exam_records';

  Future<List<Map<String, dynamic>>> getExamRecordsRaw() async {
    final list = await _getList(_kExamRecords);
    return list.cast<Map<String, dynamic>>();
  }

  Future<void> saveExamRecord(Map<String, dynamic> record) async {
    final list = await _getList(_kExamRecords);
    // prepend so newest first; keep max 50
    list.insert(0, record);
    if (list.length > 50) list.removeRange(50, list.length);
    await _setList(_kExamRecords, list);
  }
}
