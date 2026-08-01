import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/user_data_provider.dart';
import '../../providers/question_provider.dart';
import '../../providers/section_provider.dart';
import '../../providers/auth_provider.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(examAuthProvider);
    final auth = authAsync.valueOrNull;
    final wrongIds = ref.watch(wrongIdsProvider);
    final favIds = ref.watch(favoriteIdsProvider);
    final allQs = ref.watch(allQuestionsProvider);
    final allSecs = ref.watch(allSectionsProvider);

    final totalQ = allQs.maybeWhen(data: (q) => q.length, orElse: () => 942);
    final totalSecs =
        allSecs.maybeWhen(data: (s) => s.length, orElse: () => 60);
    final wrongCount =
        wrongIds.maybeWhen(data: (w) => w.length, orElse: () => 0);
    final favCount = favIds.maybeWhen(data: (f) => f.length, orElse: () => 0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('保險業務員考照',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.tertiary,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 52),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.school,
                              size: 36, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('13 章 $totalSecs 節教材',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('$totalQ 道精選題庫',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 授權 Banner
                if (auth != null && auth.isLoggedIn) ...[
                  _AuthBanner(auth: auth),
                  const SizedBox(height: 12),
                ],
                // Stats row
                Row(
                  children: [
                    _StatCard(
                        label: '題庫',
                        value: '$totalQ',
                        icon: Icons.library_books,
                        color: Colors.blue),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: '錯題',
                        value: '$wrongCount',
                        icon: Icons.error_outline,
                        color: Colors.red),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: '收藏',
                        value: '$favCount',
                        icon: Icons.bookmark,
                        color: Colors.amber),
                    const SizedBox(width: 8),
                    _StatCard(
                        label: '章節',
                        value: '13',
                        icon: Icons.menu_book,
                        color: Colors.green),
                  ],
                ),
                const SizedBox(height: 24),

                // ── 學習教材 ──────────────────────────────────
                _SectionHeader(
                    title: '學習教材與練習', icon: Icons.auto_stories),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.menu_book,
                  title: '章節閱讀',
                  subtitle: '13 章 $totalSecs 節系統教材，條理清晰',
                  color: const Color(0xFF1565C0),
                  onTap: () => context.push('/chapters'),
                ),
                const SizedBox(height: 20),

                // ── 題庫練習 ──────────────────────────────────
                _SectionHeader(title: '題庫練習', icon: Icons.quiz),
                const SizedBox(height: 10),

                _FeatureCard(
                  icon: Icons.timer,
                  title: '保險實務（50 題）',
                  subtitle: '保險實務 · 隨機抽題 · 限時 60 分鐘',
                  color: Colors.orange,
                  onTap: () => context.push('/exam?count=50&courseId=1'),
                ),
                _FeatureCard(
                  icon: Icons.assignment,
                  title: '保險法規（100 題）',
                  subtitle: '保險法規 · 完整全題型 · 限時 80 分鐘',
                  color: Colors.deepOrange,
                  onTap: () => context.push('/exam?count=100&courseId=2'),
                ),
                const SizedBox(height: 12),

                // ── 模擬考卷（線上作答）────────────────────────
                _SectionHeader(title: '模擬考卷', icon: Icons.article_outlined),
                const SizedBox(height: 10),
                // 保險實務 A / B / C 卷
                _FeatureCard(
                  icon: Icons.timer_outlined,
                  title: '保險實務 A 卷（50 題）',
                  subtitle: '保險實務 · 隨機抽題 · 限時 60 分鐘',
                  color: const Color(0xFF1565C0),
                  onTap: () => context.push(
                      '/exam?count=50&courseId=1&paper=%E4%BF%9D%E9%9A%AA%E5%AF%A6%E5%8B%99A%E5%8D%B7'),
                ),
                _FeatureCard(
                  icon: Icons.timer_outlined,
                  title: '保險實務 B 卷（50 題）',
                  subtitle: '保險實務 · 隨機抽題 · 限時 60 分鐘',
                  color: const Color(0xFF1565C0),
                  onTap: () => context.push(
                      '/exam?count=50&courseId=1&paper=%E4%BF%9D%E9%9A%AA%E5%AF%A6%E5%8B%99B%E5%8D%B7'),
                ),
                _FeatureCard(
                  icon: Icons.timer_outlined,
                  title: '保險實務 C 卷（50 題）',
                  subtitle: '保險實務 · 隨機抽題 · 限時 60 分鐘',
                  color: const Color(0xFF1565C0),
                  onTap: () => context.push(
                      '/exam?count=50&courseId=1&paper=%E4%BF%9D%E9%9A%AA%E5%AF%A6%E5%8B%99C%E5%8D%B7'),
                ),
                // 保險法規 A / B / C 卷
                _FeatureCard(
                  icon: Icons.assignment_outlined,
                  title: '保險法規 A 卷（100 題）',
                  subtitle: '保險法規 · 完整全題型 · 限時 80 分鐘',
                  color: Colors.indigo,
                  onTap: () => context.push(
                      '/exam?count=100&courseId=2&paper=%E4%BF%9D%E9%9A%AA%E6%B3%95%E8%A6%8FA%E5%8D%B7'),
                ),
                _FeatureCard(
                  icon: Icons.assignment_outlined,
                  title: '保險法規 B 卷（100 題）',
                  subtitle: '保險法規 · 完整全題型 · 限時 80 分鐘',
                  color: Colors.indigo,
                  onTap: () => context.push(
                      '/exam?count=100&courseId=2&paper=%E4%BF%9D%E9%9A%AA%E6%B3%95%E8%A6%8FB%E5%8D%B7'),
                ),
                _FeatureCard(
                  icon: Icons.assignment_outlined,
                  title: '保險法規 C 卷（100 題）',
                  subtitle: '保險法規 · 完整全題型 · 限時 80 分鐘',
                  color: Colors.indigo,
                  onTap: () => context.push(
                      '/exam?count=100&courseId=2&paper=%E4%BF%9D%E9%9A%AA%E6%B3%95%E8%A6%8FC%E5%8D%B7'),
                ),
                const SizedBox(height: 20),

                // ── 複習功能 ──────────────────────────────────
                _SectionHeader(title: '複習功能', icon: Icons.replay),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.error_outline,
                  title: '錯題本',
                  subtitle: wrongCount > 0
                      ? '共 $wrongCount 題需複習'
                      : '目前沒有錯題，繼續加油！',
                  color: Colors.red,
                  badge: wrongCount > 0 ? '$wrongCount' : null,
                  onTap: wrongCount > 0
                      ? () => context.push('/wrongbook')
                      : null,
                ),
                _FeatureCard(
                  icon: Icons.bookmark,
                  title: '收藏題目',
                  subtitle: favCount > 0
                      ? '已收藏 $favCount 題'
                      : '尚未收藏任何題目',
                  color: Colors.amber,
                  badge: favCount > 0 ? '$favCount' : null,
                  onTap:
                      favCount > 0 ? () => context.push('/favorite') : null,
                ),
                _FeatureCard(
                  icon: Icons.bar_chart,
                  title: '學習進度',
                  subtitle: '查看各章節答題統計與正確率',
                  color: Colors.green,
                  onTap: () => context.push('/progress'),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon,
            size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(value,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              Text(label,
                  style: const TextStyle(fontSize: 10),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? badge;
  final VoidCallback? onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.badge,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              (enabled ? color : Colors.grey).withOpacity(0.15),
          child: Icon(icon, color: enabled ? color : Colors.grey),
        ),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: enabled ? null : Colors.grey)),
        subtitle: Text(subtitle,
            style: const TextStyle(fontSize: 12)),
        trailing: badge != null
            ? Badge(
                label: Text(badge!),
                child: const Icon(Icons.chevron_right))
            : Icon(Icons.chevron_right,
                color: enabled ? null : Colors.grey[300]),
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}

// ──────────────────────────────────────────────
// 授權 Banner：顯示梯次 / 剩餘天數
// ──────────────────────────────────────────────
class _AuthBanner extends StatelessWidget {
  final ExamAuthState auth;
  const _AuthBanner({required this.auth});

  @override
  Widget build(BuildContext context) {
    final days = auth.daysLeft;
    final isExpiringSoon = days <= 7;
    final color = auth.isExpired
        ? Colors.red
        : isExpiringSoon
            ? Colors.orange
            : Colors.teal;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            auth.isExpired ? Icons.lock_outline : Icons.verified_user_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  auth.batchName ?? '已授權',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                if (auth.expiresAt != null)
                  Text(
                    auth.isExpired
                        ? '授權已到期'
                        : '有效至 ${auth.expiresAt!.year}/${auth.expiresAt!.month.toString().padLeft(2, "0")}/${auth.expiresAt!.day.toString().padLeft(2, "0")}（剩 $days 天）',
                    style: TextStyle(
                      color: color.withOpacity(0.8),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
