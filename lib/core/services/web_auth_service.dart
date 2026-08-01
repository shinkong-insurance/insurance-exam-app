// lib/core/services/web_auth_service.dart
// 網頁版授權：身分證號碼 + 出生年月日 核對 Supabase public.web_users

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ──────────────────────────────────────────────
// 資料模型
// ──────────────────────────────────────────────
class WebUserInfo {
  final String nationalId;
  final String name;
  final String batchName;
  final DateTime expiresAt;

  const WebUserInfo({
    required this.nationalId,
    required this.name,
    required this.batchName,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get daysLeft =>
      expiresAt.difference(DateTime.now()).inDays.clamp(0, 999);
}

enum WebLoginResult { success, notFound, expired, inactive, networkError }

// ──────────────────────────────────────────────
// 服務
// ──────────────────────────────────────────────
class WebAuthService {
  static const _kNationalId = 'web_national_id';
  static const _kName       = 'web_name';
  static const _kBatchName  = 'web_batch_name';
  static const _kExpiresAt  = 'web_expires_at';

  static final _db = Supabase.instance.client;

  // ── 登入 ──────────────────────────────────────
  static Future<({WebLoginResult result, WebUserInfo? user, String? error})>
      login(String nationalId, String birthDate) async {
    final cleanId = nationalId.trim().toUpperCase();

    try {
      final row = await _db
          .from('web_users')
          .select('national_id, name, batch_name, expires_at, is_active, login_count')
          .eq('national_id', cleanId)
          .eq('birth_date', birthDate)
          .maybeSingle();

      if (row == null) {
        return (
          result: WebLoginResult.notFound,
          user: null,
          error: '查無授權資料，請確認身分證號碼及出生年月日是否正確',
        );
      }

      if (row['is_active'] != true) {
        return (
          result: WebLoginResult.inactive,
          user: null,
          error: '此帳號已停用，請聯絡管理員',
        );
      }

      final expiresAt = DateTime.parse(row['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        final y = expiresAt.year;
        final m = expiresAt.month.toString().padLeft(2, '0');
        final d = expiresAt.day.toString().padLeft(2, '0');
        return (
          result: WebLoginResult.expired,
          user: null,
          error: '使用期限已到（$y/$m/$d），請聯絡管理員延續授權',
        );
      }

      final info = WebUserInfo(
        nationalId: cleanId,
        name: (row['name'] as String?) ?? cleanId,
        batchName: (row['batch_name'] as String?) ?? '一般學員',
        expiresAt: expiresAt,
      );

      await _saveSession(info);

      // 更新登入統計（非阻塞）
      _db
          .from('web_users')
          .update({
            'login_count': ((row['login_count'] as int?) ?? 0) + 1,
            'last_login_at': DateTime.now().toIso8601String(),
          })
          .eq('national_id', cleanId)
          .then((_) {})
          .catchError((_) {});

      return (result: WebLoginResult.success, user: info, error: null);
    } on PostgrestException catch (e) {
      return (
        result: WebLoginResult.networkError,
        user: null,
        error: '連線錯誤：${e.message}',
      );
    } catch (_) {
      return (
        result: WebLoginResult.networkError,
        user: null,
        error: '網路連線失敗，請稍後再試',
      );
    }
  }

  // ── 讀取 Session ───────────────────────────────
  static Future<WebUserInfo?> getSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nationalId   = prefs.getString(_kNationalId);
      final expiresAtStr = prefs.getString(_kExpiresAt);
      if (nationalId == null || expiresAtStr == null) return null;

      final expiresAt = DateTime.tryParse(expiresAtStr);
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        await clearSession();
        return null;
      }

      return WebUserInfo(
        nationalId: nationalId,
        name: prefs.getString(_kName) ?? nationalId,
        batchName: prefs.getString(_kBatchName) ?? '一般學員',
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  // ── 儲存 Session ───────────────────────────────
  static Future<void> _saveSession(WebUserInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNationalId, info.nationalId);
    await prefs.setString(_kName,       info.name);
    await prefs.setString(_kBatchName,  info.batchName);
    await prefs.setString(_kExpiresAt,  info.expiresAt.toIso8601String());
  }

  // ── 登出 ──────────────────────────────────────
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNationalId);
    await prefs.remove(_kName);
    await prefs.remove(_kBatchName);
    await prefs.remove(_kExpiresAt);
  }
}
