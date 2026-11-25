// lib/core/services/lk_auth_service.dart
// License Key 授權碼驗證服務

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cloud_sync_service.dart';

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
      // 伺服器端驗證（lk_login RPC）：查授權碼、檢查狀態/到期/裝置名額、記錄裝置 session。
      // 學員端不再直接讀 license_keys / key_sessions（2026-11-25 資安修補）。
      final deviceId = await getDeviceId();
      final raw = await _sb.rpc('lk_login', params: {
        'p_code': code,
        'p_device': deviceId,
      });
      final res = Map<String, dynamic>.from(raw as Map);

      switch (res['result']) {
        case 'not_found':
          return const LkLoginResponse(result: LkLoginResult.notFound);
        case 'disabled':
          return const LkLoginResponse(result: LkLoginResult.disabled);
        case 'expired':
          final exp = res['expires_at'] as String?;
          return LkLoginResponse(
            result: LkLoginResult.expired,
            expiresAt: exp == null ? null : DateTime.parse(exp),
          );
        case 'max_used':
          return const LkLoginResponse(result: LkLoginResult.maxUsed);
        case 'success':
          break;
        default:
          return LkLoginResponse(
              result: LkLoginResult.error, error: '${res['result']}');
      }

      final keyId = res['id'] as String;
      final keyCode = res['key_code'] as String;
      final expiresAt = DateTime.parse(res['expires_at'] as String);

      // 儲存 session 到 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLkKeyId, keyId);
      await prefs.setString(_kLkKeyCode, keyCode);
      await prefs.setString(_kLkBatchName, (res['batch_name'] as String?) ?? '');
      await prefs.setString(_kLkExpiresAt, res['expires_at'] as String);
      await prefs.setBool(_kLkLoggedIn, true);
      applyRequestKey(keyId);
      // 登入後立刻啟動雲端同步（原本只在開網頁時檢查一次，剛登入的第一次使用
      // 錯題／收藏不會上傳，要重新整理才會同步）
      await CloudSyncService.init();

      return LkLoginResponse(
        result: LkLoginResult.success,
        keyId: keyId,
        keyCode: keyCode,
        batchName: res['batch_name'] as String?,
        expiresAt: expiresAt,
      );
    } catch (e) {
      return LkLoginResponse(result: LkLoginResult.error, error: e.toString());
    }
  }

  // ── 請求標頭 x-lk-key ─────────────────────────
  // 資料庫 RLS 依這個標頭判斷「目前登入的授權碼」，只允許存取自己的錯題／收藏／
  // 進度、只能新增自己的作答紀錄。只加在資料庫(REST)請求，不加在 Edge Function。
  static const lkKeyHeader = 'x-lk-key';

  static void applyRequestKey(String? keyId) {
    try {
      final h = _sb.rest.headers;
      if (keyId == null || keyId.isEmpty) {
        h.remove(lkKeyHeader);
      } else {
        h[lkKeyHeader] = keyId;
      }
    } catch (_) {
      // Supabase 尚未初始化（例如測試環境）時忽略
    }
  }

  // ── 自動註冊（免碼登入）────────────────────────
  static Future<LkLoginResponse> autoRegister({
    required String name,
    required String phone,
    required DateTime examDate,
    String? referrerName,
    String? referrerPhone,
    String? referrerUnit,
    String? referrerId,
  }) async {
    try {
      final examDateStr =
          '${examDate.year.toString().padLeft(4, '0')}-'
          '${examDate.month.toString().padLeft(2, '0')}-'
          '${examDate.day.toString().padLeft(2, '0')}';

      final res = await _sb.functions.invoke('auto-register-student', body: {
        'name': name,
        'phone': phone,
        'exam_date': examDateStr,
        'referrer_name': referrerName,
        'referrer_phone': referrerPhone,
        'referrer_unit': referrerUnit,
        'referrer_id': referrerId,
      });

      final data = res.data;
      if (data is! Map || data['error'] != null) {
        final msg = (data is Map ? data['error']?.toString() : null) ?? '註冊失敗，請稍後再試';
        return LkLoginResponse(result: LkLoginResult.error, error: msg);
      }

      final keyId = data['key_id'] as String;
      final keyCode = data['key_code'] as String;
      final expiresAt = DateTime.parse(data['expires_at'] as String);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLkKeyId, keyId);
      await prefs.setString(_kLkKeyCode, keyCode);
      await prefs.setString(_kLkBatchName, 'AUTO');
      await prefs.setString(_kLkExpiresAt, expiresAt.toIso8601String());
      await prefs.setBool(_kLkLoggedIn, true);
      applyRequestKey(keyId);
      // 登入後立刻啟動雲端同步（原本只在開網頁時檢查一次，剛登入的第一次使用
      // 錯題／收藏不會上傳，要重新整理才會同步）
      await CloudSyncService.init();

      return LkLoginResponse(
        result: LkLoginResult.success,
        keyId: keyId,
        keyCode: keyCode,
        batchName: 'AUTO',
        expiresAt: expiresAt,
      );
    } on FunctionException catch (e) {
      final d = e.details;
      final msg = (d is Map && d['error'] != null) ? d['error'].toString() : '註冊失敗，請稍後再試';
      return LkLoginResponse(result: LkLoginResult.error, error: msg);
    } catch (e) {
      return LkLoginResponse(result: LkLoginResult.error, error: e.toString());
    }
  }

  // ── 讀取已儲存的 session ──────────────────────
  static Future<LkSession?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kLkLoggedIn) != true) {
      applyRequestKey(null);
      return null;
    }

    final keyId     = prefs.getString(_kLkKeyId);
    final keyCode   = prefs.getString(_kLkKeyCode);
    final batchName = prefs.getString(_kLkBatchName);
    final expiresStr = prefs.getString(_kLkExpiresAt);
    if (keyId == null || expiresStr == null) {
      applyRequestKey(null);
      return null;
    }

    final expiresAt = DateTime.parse(expiresStr);
    if (expiresAt.isBefore(DateTime.now())) {
      // 已到期，清除 session
      await logout();
      return null;
    }

    applyRequestKey(keyId);
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
    applyRequestKey(null);
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
