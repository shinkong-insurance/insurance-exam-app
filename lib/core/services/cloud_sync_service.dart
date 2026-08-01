// lib/core/services/cloud_sync_service.dart
// 授權碼模式下，將收藏／錯題雙向同步到 Supabase
// 設計：App 啟動時從雲端拉取 → 本地操作後立即推送

import 'package:supabase_flutter/supabase_flutter.dart';
import 'lk_auth_service.dart';

class CloudSyncService {
  static final _sb = Supabase.instance.client;

  // ── 是否處於 LK 模式 ──────────────────────────
  static LkSession? _session;

  static Future<bool> init() async {
    _session = await LkAuthService.getSession();
    return _session != null;
  }

  static bool get isLkMode => _session != null;

  static String get _keyId => _session?.keyId ?? '';
  static String get _deviceId => _session?.deviceId ?? '';

  // ════════════════════════════════════════════════
  // 收藏 (Favorites)
  // ════════════════════════════════════════════════

  /// 從 Supabase 拉取此 key 的全部收藏題目 ID
  static Future<Set<String>> fetchFavorites() async {
    if (!isLkMode) return {};
    try {
      final res = await _sb
          .from('key_favorites')
          .select('question_id')
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId);
      return (res as List)
          .map((r) => r['question_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// 加入收藏
  static Future<void> addFavorite(String questionId) async {
    if (!isLkMode) return;
    try {
      await _sb.from('key_favorites').upsert({
        'key_id': _keyId,
        'device_id': _deviceId,
        'question_id': questionId,
      }, onConflict: 'key_id,device_id,question_id');
    } catch (_) {}
  }

  /// 移除收藏
  static Future<void> removeFavorite(String questionId) async {
    if (!isLkMode) return;
    try {
      await _sb.from('key_favorites')
          .delete()
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId)
          .eq('question_id', questionId);
    } catch (_) {}
  }

  // ════════════════════════════════════════════════
  // 錯題 (Wrong Answers)
  // ════════════════════════════════════════════════

  /// 從 Supabase 拉取此 key 的全部錯題
  static Future<Map<String, int>> fetchWrongAnswers() async {
    if (!isLkMode) return {};
    try {
      final res = await _sb
          .from('key_wrong_answers')
          .select('question_id, wrong_count')
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId);
      return Map.fromEntries(
        (res as List).map((r) => MapEntry(
          r['question_id'] as String,
          (r['wrong_count'] as int?) ?? 1,
        )),
      );
    } catch (_) {
      return {};
    }
  }

  /// 記錄錯題（wrong_count + 1）
  static Future<void> recordWrong(String questionId) async {
    if (!isLkMode) return;
    try {
      // 先查看是否已有記錄
      final existing = await _sb
          .from('key_wrong_answers')
          .select('id, wrong_count')
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId)
          .eq('question_id', questionId)
          .maybeSingle();

      if (existing == null) {
        await _sb.from('key_wrong_answers').insert({
          'key_id': _keyId,
          'device_id': _deviceId,
          'question_id': questionId,
          'wrong_count': 1,
          'last_wrong_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _sb.from('key_wrong_answers').update({
          'wrong_count': ((existing['wrong_count'] as int?) ?? 0) + 1,
          'last_wrong_at': DateTime.now().toIso8601String(),
        })
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId)
          .eq('question_id', questionId);
      }
    } catch (_) {}
  }

  /// 從錯題本移除（答對後可呼叫）
  static Future<void> removeWrong(String questionId) async {
    if (!isLkMode) return;
    try {
      await _sb.from('key_wrong_answers')
          .delete()
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId)
          .eq('question_id', questionId);
    } catch (_) {}
  }

  /// 清空所有錯題（重置）
  static Future<void> clearAllWrong() async {
    if (!isLkMode) return;
    try {
      await _sb.from('key_wrong_answers')
          .delete()
          .eq('key_id', _keyId)
          .eq('device_id', _deviceId);
    } catch (_) {}
  }

  // ── 重置 session（登出時呼叫） ────────────────
  static void reset() {
    _session = null;
  }
}
