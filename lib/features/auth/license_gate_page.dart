// lib/features/auth/license_gate_page.dart
// 身份驗證頁：身分證號碼 + 出生年月日

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/web_auth_service.dart';
import '../../providers/auth_provider.dart';

class LicenseGatePage extends ConsumerStatefulWidget {
  const LicenseGatePage({super.key});

  @override
  ConsumerState<LicenseGatePage> createState() => _LicenseGatePageState();
}

class _LicenseGatePageState extends ConsumerState<LicenseGatePage> {
  final _idController = TextEditingController();

  int? _year;
  int? _month;
  int? _day;
  bool _loading = false;
  String? _errorMsg;

  static const int _minYear = 1940;
  static final int _maxYear = DateTime.now().year - 15;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  String? _buildBirthDate() {
    if (_year == null || _month == null || _day == null) return null;
    final m = _month!.toString().padLeft(2, '0');
    final d = _day!.toString().padLeft(2, '0');
    return '$_year-$m-$d';
  }

  bool _validateId(String id) {
    if (id.length != 10) return false;
    return RegExp(r'^[A-Z][12][0-9]{8}$').hasMatch(id);
  }

  int _daysInMonth() {
    if (_year == null || _month == null) return 31;
    return DateUtils.getDaysInMonth(_year!, _month!);
  }

  Future<void> _login() async {
    final id = _idController.text.trim().toUpperCase();
    final birthDate = _buildBirthDate();

    if (!_validateId(id)) {
      setState(() => _errorMsg = '身分證號碼格式不正確\n首字大寫英文 + 9 位數字，第二碼須為 1 或 2');
      return;
    }
    if (birthDate == null) {
      setState(() => _errorMsg = '請選擇完整的出生年月日');
      return;
    }

    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    final res = await WebAuthService.login(id, birthDate);

    if (!mounted) return;
    setState(() => _loading = false);

    if (res.result == WebLoginResult.success) {
      await ref.read(examAuthProvider.notifier).refresh();
      if (mounted) context.go('/');
    } else {
      setState(() => _errorMsg = res.error ?? '驗證失敗，請重試');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          // ── 主要內容 ──────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Logo ─────────────────────────────
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade700,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_user,
                              color: Colors.white, size: 48),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        '保險業務員資格測驗',
                        style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '請輸入身分資料以驗證授權',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white60),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // ── 身分證號碼 ─────────────────────────
                      _fieldLabel('身分證號碼'),
                      const SizedBox(height: 6),
                      _inputBox(
                        hasError: _errorMsg != null,
                        child: TextField(
                          controller: _idController,
                          enabled: !_loading,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 20,
                            letterSpacing: 3,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: 'A123456789',
                            hintStyle:
                                TextStyle(color: Colors.white30, fontSize: 16),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]')),
                            LengthLimitingTextInputFormatter(10),
                            _UpperCaseFormatter(),
                          ],
                          onSubmitted: (_) => _login(),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── 出生年月日 ─────────────────────────
                      _fieldLabel('出生年月日'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 35,
                            child: _dropdown<int>(
                              hint: '年',
                              value: _year,
                              items: List.generate(
                                  _maxYear - _minYear + 1, (i) => _maxYear - i),
                              label: (v) => '$v 年',
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() {
                                        _year = v;
                                        _day = null;
                                      }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 25,
                            child: _dropdown<int>(
                              hint: '月',
                              value: _month,
                              items: List.generate(12, (i) => i + 1),
                              label: (v) => '$v 月',
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() {
                                        _month = v;
                                        _day = null;
                                      }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 25,
                            child: _dropdown<int>(
                              hint: '日',
                              value: _day,
                              items:
                                  List.generate(_daysInMonth(), (i) => i + 1),
                              label: (v) => '$v 日',
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() => _day = v),
                            ),
                          ),
                        ],
                      ),

                      // ── 錯誤訊息 ───────────────────────────
                      if (_errorMsg != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ── 登入按鈕 ───────────────────────────
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('驗證身份並進入'),
                        ),
                      ),

                      const SizedBox(height: 28),

                      Text(
                        '授權由教育訓練單位管理\n如有問題請聯絡課程負責人',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white38),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── 右上角管理員入口 ──────────────────────
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Tooltip(
                  message: '管理員後台',
                  child: IconButton(
                    icon: const Icon(Icons.admin_panel_settings,
                        color: Colors.white12, size: 22),
                    onPressed: () => context.push('/admin-login'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 輔助 Widget ────────────────────────────────

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
            color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
      );

  Widget _inputBox({required bool hasError, required Widget child}) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: hasError ? Colors.red.shade400 : Colors.white24),
        ),
        child: child,
      );

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required void Function(T?)? onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint,
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
          dropdownColor: const Color(0xFF16213E),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          underline: const SizedBox(),
          isExpanded: true,
          onChanged: onChanged,
          items: items
              .map((v) => DropdownMenuItem(value: v, child: Text(label(v))))
              .toList(),
        ),
      );
}

// ── Formatter ──────────────────────────────────
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
          TextEditingValue old, TextEditingValue val) =>
      val.copyWith(text: val.text.toUpperCase());
}
