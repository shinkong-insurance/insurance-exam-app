// lib/core/services/device_service.dart
// 產生 Device Fingerprint，用於綁定裝置防止帳號共用

import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// 回傳 32 字元 SHA-256 fingerprint
  static Future<String> getFingerprint() async {
    String raw = '';

    try {
      if (kIsWeb) {
        final info = await _deviceInfo.webBrowserInfo;
        raw = '${info.userAgent ?? ""}_${info.platform ?? ""}_${info.vendor ?? ""}';
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        raw = '${info.id}_${info.model}_${info.brand}_${info.serialNumber}';
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        raw = '${info.identifierForVendor ?? info.model}_${info.systemName}';
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        raw = '${info.deviceId}_${info.computerName}';
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        raw = '${info.systemGUID ?? info.model}_${info.computerName}';
      } else {
        raw = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (_) {
      raw = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }

    final bytes = utf8.encode(raw);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32);
  }

  /// 平台名稱
  static String getPlatform() {
    if (kIsWeb) return 'Web';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    return 'Unknown';
  }
}
