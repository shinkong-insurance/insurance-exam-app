// lib/features/auth/lk_gate_page.dart
// 授權碼 (License Key) 登入頁

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/lk_auth_service.dart';

class LkGatePage extends StatefulWidget {
  const LkGatePage({super.key});

  @override
  State<LkGatePage> createState() => _LkGatePageState();
}

class _LkGatePageState extends State<LkGatePage> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    final session = await LkAuthService.getSession();
    if (session != null && mounted) {
      context.go('/');
    }
  }

  Future<void> _login() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _errorMsg = '請輸入授權碼');
      return;
    }
    if (!RegExp(r'^SK-\d{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$').hasMatch(code)) {
      setState(() => _errorMsg = '授權碼格式不正確\n範例：SK-2026-ABCD-1234');
      return;
    }

    setState(() { _loading = true; _errorMsg = null; });

    final res = await LkAuthService.login(code);

    if (!mounted) return;
    setState(() => _loading = false);

    switch (res.result) {
      case LkLoginResult.success:
        context.go('/');
      case LkLoginResult.notFound:
        setState(() => _errorMsg = '找不到此授權碼，請確認後重試');
      case LkLoginResult.expired:
        setState(() => _errorMsg = '此授權碼已於 ${res.expiresAt?.toLocal().toString().substring(0,10)} 到期');
      case LkLoginResult.maxUsed:
        setState(() => _errorMsg = '此授權碼使用名額已滿，請洽管理人員');
      case LkLoginResult.disabled:
        setState(() => _errorMsg = '此授權碼已停用，請洽管理人員');
      case LkLoginResult.error:
        setState(() => _errorMsg = '驗證失敗：${res.error}');
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
                      // ── Logo ─────────────────────
                      Center(
                        child: Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.vpn_key_rounded,
                              color: Colors.white, size: 44),
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
                        '請輸入課程授權碼以開始學習',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white60),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 36),

                      // ── 授權碼輸入 ────────────────
                      const Text(
                        '授權碼',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF16213E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _errorMsg != null ? Colors.red.shade400 : Colors.white24,
                          ),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          enabled: !_loading,
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 18,
                            letterSpacing: 2,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            hintText: 'SK-2026-ABCD-1234',
                            hintStyle: TextStyle(color: Colors.white30, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
                            LengthLimitingTextInputFormatter(17), // SK-YYYY-XXXX-NNNN = 17 chars with dashes
                            _LkFormatter(),
                          ],
                          onSubmitted: (_) => _login(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '授權碼由教育訓練單位提供，格式為 SK-YYYY-XXXX-NNNN',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),

                      // ── 錯誤訊息 ──────────────────
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

                      // ── 登入按鈕 ──────────────────
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : const Text('驗證授權碼並進入'),
                        ),
                      ),

                      const SizedBox(height: 28),
                      Text(
                        '授權碼由教育訓練單位管理\n如有問題請聯絡課程負責人',
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

          // ── 右上角管理員入口 ───────────────────
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
}

// ── 自動格式化：SK-XXXX-XXXX-XXXX ────────────
class _LkFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.toUpperCase().replaceAll('-', '');
    final buf = StringBuffer();
    for (int i = 0; i < text.length && i < 14; i++) {
      if (i == 2 || i == 6 || i == 10) buf.write('-');
      buf.write(text[i]);
    }
    final result = buf.toString();
    return newValue.copyWith(
      text: result,
      selection: TextSelection.collapsed(offset: result.length),
    );
  }
}
