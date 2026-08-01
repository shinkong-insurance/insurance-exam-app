// lib/core/services/auth_service.dart
// License Key 驗證 + Device 綁定 + Supabase Auth

import 'package:supabase_flutter/supabase_flutter.dart';
import 'device_service.dart';

enum AuthResult {
  success,
  invalidKey,
  expiredKey,
  alreadyUsedOnOtherDevice,
  networkError,
  unknown,
}

class LicenseInfo {
  final String key;
  final String batchName;
  final DateTime expiresAt;
  final List<int> allowedChapters;
  final bool canMockExam;
  final bool canWrongBook;

  LicenseInfo({
    required this.key,
    required this.batchName,
    required this.expiresAt,
    required this.allowedChapters,
    required this.canMockExam,
    required this.canWrongBook,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class AuthService {
  static final _supabase = Supabase.instance.client;

  // ──────────────────────────────────────────────
  // 首次啟用 License Key
  // ──────────────────────────────────────────────
  static Future<({AuthResult result, LicenseInfo? info, String? error})>
      activateLicense(String key) async {
    final cleanKey = key.trim().toUpperCase();

    try {
      // 1. 查詢 License
      final licenseRow = await _supabase
          .schema('exam')
          .from('licenses')
          .select('id, key, batch_id, max_devices, is_used, expires_at, batches(name, allowed_chapters, can_mock_exam, can_wrong_book, is_active)')
          .eq('key', cleanKey)
          .maybeSingle();

      if (licenseRow == null) {
        return (result: AuthResult.invalidKey, info: null, error: '授權碼無效，請確認輸入是否正確');
      }

      // 2. 確認到期
      final expiresAt = DateTime.parse(licenseRow['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        return (result: AuthResult.expiredKey, info: null, error: '此授權碼已過期，請聯絡管理員');
      }

      // 3. 確認梯次有效
      final batch = licenseRow['batches'] as Map<String, dynamic>;
      if (batch['is_active'] == false) {
        return (result: AuthResult.expiredKey, info: null, error: '此梯次已停用，請聯絡管理員');
      }

      // 4. 取得 Device Fingerprint
      final fingerprint = await DeviceService.getFingerprint();
      final platform = DeviceService.getPlatform();

      // 5. 若 License 已被使用，檢查是否同一裝置
      if (licenseRow['is_used'] == true) {
        final licenseId = licenseRow['id'] as String;
        // 找已登入的 auth user（若有）
        final existingUser = _supabase.auth.currentUser;
        if (existingUser != null) {
          // 比對裝置
          final binding = await _supabase
              .schema('exam')
              .from('device_bindings')
              .select('device_fingerprint')
              .eq('student_id', existingUser.id)
              .eq('device_fingerprint', fingerprint)
              .maybeSingle();

          if (binding != null) {
            // 同一裝置，允許繼續
            return _buildSuccess(licenseRow, batch, expiresAt);
          }
        }
        return (result: AuthResult.alreadyUsedOnOtherDevice, info: null,
            error: '此授權碼已綁定其他裝置。如需換裝置，請聯絡管理員解除綁定');
      }

      // 6. 建立匿名 Auth User（用 license key 作為 email）
      final email = '${cleanKey.toLowerCase()}@examapp.internal';
      final password = 'SK${fingerprint.substring(0, 16)}';

      AuthResponse authResp;
      try {
        authResp = await _supabase.auth.signUp(email: email, password: password);
      } catch (_) {
        // 可能已存在，改登入
        authResp = await _supabase.auth.signInWithPassword(email: email, password: password);
      }

      final userId = authResp.user?.id;
      if (userId == null) throw Exception('Auth 建立失敗');

      // 7. 建立 student 記錄
      await _supabase.schema('exam').from('students').upsert({
        'id': userId,
        'batch_id': licenseRow['batch_id'],
        'license_id': licenseRow['id'],
      });

      // 8. 綁定裝置
      await _supabase.schema('exam').from('device_bindings').upsert({
        'student_id': userId,
        'device_fingerprint': fingerprint,
        'platform': platform,
        'is_active': true,
      });

      // 9. 標記 License 已使用
      await _supabase
          .schema('exam')
          .from('licenses')
          .update({'is_used': true, 'activated_at': DateTime.now().toIso8601String()})
          .eq('key', cleanKey);

      // 10. 寫入登入紀錄
      await _supabase.schema('exam').from('login_logs').insert({
        'student_id': userId,
        'license_key': cleanKey,
        'device_fingerprint': fingerprint,
        'platform': platform,
        'success': true,
      });

      return _buildSuccess(licenseRow, batch, expiresAt);
    } on PostgrestException catch (e) {
      return (result: AuthResult.networkError, info: null, error: '連線錯誤：${e.message}');
    } catch (e) {
      return (result: AuthResult.unknown, info: null, error: '未知錯誤：$e');
    }
  }

  // ──────────────────────────────────────────────
  // 每次啟動驗證（已有 session）
  // ──────────────────────────────────────────────
  static Future<({bool valid, String? error})> verifySession() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return (valid: false, error: null);

      // 查 student + license 到期
      final student = await _supabase
          .schema('exam')
          .from('students')
          .select('license_id, licenses(expires_at, is_used)')
          .eq('id', user.id)
          .maybeSingle();

      if (student == null) return (valid: false, error: null);

      final license = student['licenses'] as Map<String, dynamic>?;
      if (license == null) return (valid: false, error: null);

      final expiresAt = DateTime.parse(license['expires_at'] as String);
      if (DateTime.now().isAfter(expiresAt)) {
        return (valid: false, error: '使用期限已到（${expiresAt.year}/${expiresAt.month}/${expiresAt.day}），請聯絡管理員');
      }

      // 驗證 Device
      final fingerprint = await DeviceService.getFingerprint();
      final binding = await _supabase
          .schema('exam')
          .from('device_bindings')
          .select('id')
          .eq('student_id', user.id)
          .eq('device_fingerprint', fingerprint)
          .eq('is_active', true)
          .maybeSingle();

      if (binding == null) {
        return (valid: false, error: '裝置驗證失敗，請聯絡管理員');
      }

      return (valid: true, error: null);
    } catch (_) {
      // 網路錯誤時暫時允許（避免離線時無法使用）
      return (valid: true, error: null);
    }
  }

  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // ──────────────────────────────────────────────
  // 私有 helper
  // ──────────────────────────────────────────────
  static ({AuthResult result, LicenseInfo? info, String? error}) _buildSuccess(
    Map<String, dynamic> licenseRow,
    Map<String, dynamic> batch,
    DateTime expiresAt,
  ) {
    final rawChapters = batch['allowed_chapters'] as List<dynamic>? ?? [];
    return (
      result: AuthResult.success,
      info: LicenseInfo(
        key: licenseRow['key'] as String,
        batchName: batch['name'] as String,
        expiresAt: expiresAt,
        allowedChapters: rawChapters.map((e) => e as int).toList(),
        canMockExam: batch['can_mock_exam'] as bool? ?? true,
        canWrongBook: batch['can_wrong_book'] as bool? ?? true,
      ),
      error: null,
    );
  }
}
