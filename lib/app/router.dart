// lib/app/router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/services/web_auth_service.dart';
import '../core/services/lk_auth_service.dart';
import '../features/auth/license_gate_page.dart';
import '../features/auth/lk_gate_page.dart';
import '../features/auth/license_expired_page.dart';
import '../features/admin/admin_login_page.dart';
import '../features/admin/admin_dashboard_page.dart';
import '../features/home/home_page.dart';
import '../features/chapter/chapter_list_page.dart';
import '../features/chapter/chapter_detail_page.dart';
import '../features/section/section_reading_page.dart';
import '../features/quiz/quiz_page.dart';
import '../features/exam/exam_page.dart';
import '../features/exam/exam_result_page.dart';
import '../features/wrongbook/wrong_book_page.dart';
import '../features/favorite/favorite_page.dart';
import '../features/progress/progress_page.dart';
import '../features/image_review/image_review_page.dart';

// ──────────────────────────────────────────────
// 授權守衛（支援兩種登入模式）
// ──────────────────────────────────────────────
Future<String?> _authGuard(BuildContext context, GoRouterState state) async {
  final loc = state.matchedLocation;

  // 免驗證頁面直接放行
  if (loc == '/license' ||
      loc == '/lk' ||
      loc == '/expired' ||
      loc == '/admin-login' ||
      loc == '/admin') return null;

  // ① 身分證版 session
  final user = await WebAuthService.getSession();
  if (user != null) return null;

  // ② 授權碼版 session
  final lkSession = await LkAuthService.getSession();
  if (lkSession != null) return null;

  // 兩者皆無 → 導向身分證登入頁（預設）
  return '/license';
}

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: _authGuard,
  routes: [
    // ── 授權頁 ──────────────────────────────
    GoRoute(path: '/license', builder: (_, __) => const LicenseGatePage()),
    GoRoute(path: '/lk',      builder: (_, __) => const LkGatePage()),
    GoRoute(
      path: '/expired',
      builder: (_, state) => LicenseExpiredPage(
        message: state.uri.queryParameters['msg'] ?? '使用期限已到，請聯絡管理員',
      ),
    ),

    // ── 管理後台 ────────────────────────────
    GoRoute(path: '/admin-login', builder: (_, __) => const AdminLoginPage()),
    GoRoute(path: '/admin',       builder: (_, __) => const AdminDashboardPage()),

    // ── 主功能頁 ────────────────────────────
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(path: '/chapters', builder: (_, __) => const ChapterListPage()),
    GoRoute(
      path: '/chapter/:chapterId',
      builder: (_, state) => ChapterDetailPage(
        chapterId: int.parse(state.pathParameters['chapterId']!),
      ),
    ),
    GoRoute(
      path: '/section/:chapterId/:sectionId',
      builder: (_, state) => SectionReadingPage(
        chapterId: int.parse(state.pathParameters['chapterId']!),
        sectionId: int.parse(state.pathParameters['sectionId']!),
      ),
    ),
    GoRoute(
      path: '/quiz/:chapterId',
      builder: (_, state) => QuizPage(
        chapterId: int.parse(state.pathParameters['chapterId']!),
        isWrongBook: state.uri.queryParameters['wrong'] == 'true',
        isFavorite: state.uri.queryParameters['fav'] == 'true',
      ),
    ),
    GoRoute(
      path: '/exam',
      builder: (_, state) => ExamPage(
        count: int.parse(state.uri.queryParameters['count'] ?? '50'),
        chapterId: state.uri.queryParameters['chapter'] != null
            ? int.parse(state.uri.queryParameters['chapter']!)
            : null,
        courseId: state.uri.queryParameters['courseId'] != null
            ? int.parse(state.uri.queryParameters['courseId']!)
            : null,
        wrongPriority: state.uri.queryParameters['wrongPriority'] == 'true',
        paperName: state.uri.queryParameters['paper'],
      ),
    ),
    GoRoute(
      path: '/exam-result',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return ExamResultPage(result: extra);
      },
    ),
    GoRoute(path: '/wrongbook',    builder: (_, __) => const WrongBookPage()),
    GoRoute(path: '/favorite',     builder: (_, __) => const FavoritePage()),
    GoRoute(path: '/progress',     builder: (_, __) => const ProgressPage()),
    GoRoute(path: '/image-review', builder: (_, __) => const ImageReviewPage()),
  ],
);
