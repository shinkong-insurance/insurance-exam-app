// lib/core/services/lk_auth_service.dart
// License Key 授權碼驗證服務

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── 驗證結果 ──────────────────────────────────
enum LkLoginResult { success, notFound, expired, maxUsed, disabled, error }

class LkLoginResponse {
  final LkLoginResult result;
  final String? keyId;
  final String? keyCode;
  final String? batchName;
  final DateTime? expiresAt;
  final String? error;

  const LkLoginResponse({
    required this.result,
    this.keyId,
    this.keyCode,
    this.batchName,
    this.expiresAt,
    this.error,
  });
}

// ── SharedPreferences 儲存 key ─────────────────
const _kLkKeyId      = 'lk_key_id';
const _kLkKeyCode    = 'lk_key_code';
const _kLkBatchName  = 'lk_batch_name';
const _kLkExpiresAt  = 'lk_expires_at';
const _kLkDeviceId   = 'lk_device_id';
const _kLkLoggedIn   = 'lk_logged_in';

class LkAuthService {
  static final _sb = Supabase.instance.client;

  // ── 取得或建立裝置 ID ──────────────────────────
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_kLkDeviceId);
    if (id == null) {
      id = 'web_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      await prefs.setString(_kLkDeviceId, id);
    }
    return id;
  }

  // ── 授權碼登入 ────────────────────────────────
  static Future<LkLoginResponse> login(String rawCode) async {
    final code = rawCode.trim().toUpperCase();

    try {
      // 1. 查詢授權碼
      final res = await _sb
          .from('license_keys')
          .select('id, key_code, batch_name, max_uses, used_count, expires_at, is_active')
          .eq('key_code', code)
          .maybeSingle();

      if (res == null) return const LkLoginResponse(result: LkLoginResult.notFound);

      // 2. 狀態檢查
      if (res['is_active'] == false) {
        return const LkLoginResponse(result: LkLoginResult.disabled);
      }

      final expiresAt = DateTime.parse(res['expires_at'] as String);
      if (expiresAt.isBefore(DateTime.now())) {
        return LkLoginResponse(
          result: LkLoginResult.expired,
          expiresAt: expiresAt,
        );
      }

      final maxUses = (res['max_uses'] as int?) ?? 1;
      final usedCount = (res['used_count'] as int?) ?? 0;
      final keyId = res['id'] as String;
      final deviceId = await getDeviceId();

      // 3. max_uses 檢查（0 = 無限；每裝置獨立計算，同裝置再次登入不佔用名額）
      if (maxUses > 0) {
        // 查看此裝置是否已用過此授權碼
        final sessionRes = await _sb
            .from('key_sessions')
            .select('id')
            .eq('key_id', keyId)
            .eq('device_id', deviceId)
            .maybeSingle();

        final isNewDevice = sessionRes == null;
        if (isNewDevice && usedCount >= maxUses) {
          return const LkLoginResponse(result: LkLoginResult.maxUsed);
        }
      }

      // 4. upsert session + 更新 used_count
      await _upsertSession(keyId, deviceId, maxUses > 0);

      // 5. 儲存 session 到 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLkKeyId, keyId);
      await prefs.setString(_kLkKeyCode, res['key_code'] as String);
      await prefs.setString(_kLkBatchName, (res['batch_name'] as String?) ?? '');
      await prefs.setString(_kLkExpiresAt, res['expires_at'] as String);
      await prefs.setBool(_kLkLoggedIn, true);

      return LkLoginResponse(
        result: LkLoginResult.success,
        keyId: keyId,
        keyCode: res['key_code'] as String,
        batchName: res['batch_name'] as String?,
        expiresAt: expiresAt,
      );
    } catch (e) {
      return LkLoginResponse(result: LkLoginResult.error, error: e.toString());
    }
  }

  // ── upsert key_sessions 並更新 used_count ────
  static Future<void> _upsertSession(String keyId, String deviceId, bool trackUses) async {
    // 先確認是否已有 session
    final existing = await _sb
        .from('key_sessions')
        .select('id, login_count')
        .eq('key_id', keyId)
        .eq('device_id', deviceId)
        .maybeSingle();

    if (existing == null) {
      // 新裝置
      await _sb.from('key_sessions').insert({
        'key_id': keyId,
        'device_id': deviceId,
        'login_count': 1,
      });
      // 遞增 used_count
      if (trackUses) {
        await _sb.rpc('increment_key_used_count', params: {'k_id': keyId});
      }
    } else {
      // 已有裝置 → 只更新 login_count 和 last_used_at
      await _sb.from('key_sessions').update({
        'login_count': ((existing['login_count'] as int?) ?? 0) + 1,
        'last_used_at': DateTime.now().toIso8601String(),
      }).eq('key_id', keyId).eq('device_id', deviceId);
    }
  }

  // ── 讀取已儲存的 session ──────────────────────
  static Future<LkSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kLkLoggedIn) != true) return null;

    final keyId     = prefs.getString(_kLkKeyId);
    final keyCode   = prefs.getString(_kLkKeyCode);
    final batchName = prefs.getString(_kLkBatchName);
    final expiresStr = prefs.getString(_kLkExpiresAt);
    if (keyId == null || expiresStr == null) return null;

    final expiresAt = DateTime.parse(expiresStr);
    if (expiresAt.isBefore(DateTime.now())) {
      // 已到期，清除 session
      await logout();
      return null;
    }

    return LkSession(
      keyId: keyId,
      keyCode: keyCode ?? '',
      batchName: batchName ?? '',
      expiresAt: expiresAt,
      deviceId: prefs.getString(_kLkDeviceId) ?? '',
    );
  }

  // ── 登出 ──────────────────────────────────────
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kLkKeyId);
    await prefs.remove(_kLkKeyCode);
    await prefs.remove(_kLkBatchName);
    await prefs.remove(_kLkExpiresAt);
    await prefs.remove(_kLkLoggedIn);
    // _kLkDeviceId 保留，避免下次登入佔用新的 used_count 名額
  }
}

// ── Session 資料模型 ──────────────────────────
class LkSession {
  final String keyId;
  final String keyCode;
  final String batchName;
  final DateTime expiresAt;
  final String deviceId;

  const LkSession({
    required this.keyId,
    required this.keyCode,
    required this.batchName,
    required this.expiresAt,
    required this.deviceId,
  });

  bool get isExpired => expiresAt.isBefore(DateTime.now());

  int get daysRemaining => expiresAt.difference(DateTime.now()).inDays;
}
