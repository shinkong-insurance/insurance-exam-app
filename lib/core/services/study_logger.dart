// lib/core/services/study_logger.dart
// 學習行為事件追蹤服務 — fire-and-forget，絕不影響 APP 主流程

import 'package:supabase_flutter/supabase_flutter.dart';
import 'lk_auth_service.dart';

class StudyLogger {
  static final _sb = Supabase.instance.client;

  // ── 取得目前登入的授權碼（無 session 回 'unknown'）─────
  static Future<String> _getLicenseKey() async {
    try {
      final session = await LkAuthService.getSession();
      return session?.keyCode ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  // ── 底層插入（靜默失敗，不拋例外）──────────────────────
  static Future<void> _insert(Map<String, dynamic> data) async {
    try {
      await _sb.from('study_logs').insert(data);
    } catch (_) {
      // 追蹤失敗不應中斷學習體驗，靜默忽略
    }
  }

  // ────────────────────────────────────────────────────────
  // 公開 API
  // ────────────────────────────────────────────────────────

  /// 授權碼登入成功
  static void login(String licenseKey) {
    _insert({
      'license_key': licenseKey,
      'event_type': 'login',
    });
  }

  /// 章節/小節閱讀結束（停留秒數）
  static Future<void> chapterRead({
    required int chapterId,
    required int sectionId,
    required int durationSeconds,
  }) async {
    if (durationSeconds < 3) return; // 少於 3 秒視為誤觸，不記錄
    final key = await _getLicenseKey();
    _insert({
      'license_key': key,
      'event_type': 'chapter_read',
      'chapter_id': '$chapterId',
      'section_id': '$sectionId',
      'duration_seconds': durationSeconds,
    });
  }

  /// 練習或模擬考完成
  static Future<void> quizSession({
    required int questionsTotal,
    required int questionsCorrect,
    int? chapterId,
    int? courseId,
    bool isMockExam = false,
  }) async {
    final key = await _getLicenseKey();
    final meta = <String, dynamic>{};
    if (courseId != null) meta['course_id'] = courseId;
    if (isMockExam) meta['is_mock'] = true;

    _insert({
      'license_key': key,
      'event_type': isMockExam ? 'exam_session' : 'quiz_session',
      if (chapterId != null) 'chapter_id': '$chapterId',
      'questions_total': questionsTotal,
      'questions_correct': questionsCorrect,
      'metadata': meta,
    });
  }
}
