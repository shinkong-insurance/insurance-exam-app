// lib/providers/auth_provider.dart
// 全 APP 共享的授權狀態（基於 web_users + SharedPreferences session）

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/web_auth_service.dart';

// ──────────────────────────────────────────────
// 資料模型
// ──────────────────────────────────────────────
class ExamAuthState {
  final bool isLoggedIn;
  final bool isLoading;
  final String? name;
  final String? batchName;
  final DateTime? expiresAt;
  final List<int> allowedChapters; // 空 = 全部開放
  final bool canMockExam;
  final bool canWrongBook;
  final String? errorMsg;

  const ExamAuthState({
    this.isLoggedIn = false,
    this.isLoading = true,
    this.name,
    this.batchName,
    this.expiresAt,
    this.allowedChapters = const [],
    this.canMockExam = true,
    this.canWrongBook = true,
    this.errorMsg,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  int get daysLeft => expiresAt == null
      ? 0
      : expiresAt!.difference(DateTime.now()).inDays.clamp(0, 999);

  ExamAuthState copyWith({
    bool? isLoggedIn,
    bool? isLoading,
    String? name,
    String? batchName,
    DateTime? expiresAt,
    List<int>? allowedChapters,
    bool? canMockExam,
    bool? canWrongBook,
    String? errorMsg,
  }) =>
      ExamAuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        isLoading: isLoading ?? this.isLoading,
        name: name ?? this.name,
        batchName: batchName ?? this.batchName,
        expiresAt: expiresAt ?? this.expiresAt,
        allowedChapters: allowedChapters ?? this.allowedChapters,
        canMockExam: canMockExam ?? this.canMockExam,
        canWrongBook: canWrongBook ?? this.canWrongBook,
        errorMsg: errorMsg,
      );
}

// ──────────────────────────────────────────────
// Notifier
// ──────────────────────────────────────────────
class ExamAuthNotifier extends AsyncNotifier<ExamAuthState> {
  @override
  Future<ExamAuthState> build() async => _loadState();

  Future<ExamAuthState> _loadState() async {
    final user = await WebAuthService.getSession();
    if (user == null) {
      return const ExamAuthState(isLoggedIn: false, isLoading: false);
    }
    return ExamAuthState(
      isLoggedIn: true,
      isLoading: false,
      name: user.name,
      batchName: user.batchName,
      expiresAt: user.expiresAt,
      allowedChapters: const [], // 空 = 全部開放
      canMockExam: true,
      canWrongBook: true,
    );
  }

  /// 登入後刷新狀態
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = AsyncValue.data(await _loadState());
  }

  /// 登出
  Future<void> signOut() async {
    await WebAuthService.clearSession();
    state = const AsyncValue.data(
      ExamAuthState(isLoggedIn: false, isLoading: false),
    );
  }
}

// ──────────────────────────────────────────────
// Provider（全域單例）
// ──────────────────────────────────────────────
final examAuthProvider =
    AsyncNotifierProvider<ExamAuthNotifier, ExamAuthState>(
  ExamAuthNotifier.new,
);

/// 便捷 provider：章節是否允許存取（web 版全開放）
final chapterAllowedProvider = Provider.family<bool, int>((ref, chapterId) {
  final auth = ref.watch(examAuthProvider).valueOrNull;
  if (auth == null || !auth.isLoggedIn) return false;
  if (auth.allowedChapters.isEmpty) return true; // 空 = 全開放
  return auth.allowedChapters.contains(chapterId);
});
