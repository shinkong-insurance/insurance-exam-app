// lib/features/admin/admin_dashboard_page.dart
// 管理後台主頁：web_users CRUD

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'widgets/user_form_modal.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      if (mounted) context.go('/admin-login');
      return;
    }
    await _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('web_users')
          .select()
          .order('created_at', ascending: false);
      setState(() {
        _users = List<Map<String, dynamic>>.from(data);
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗：$e'), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _applyFilter() {
    final q = _query.toLowerCase();
    _filtered = q.isEmpty
        ? List.from(_users)
        : _users.where((u) {
            return (u['name'] ?? '').toLowerCase().contains(q) ||
                (u['national_id'] ?? '').toLowerCase().contains(q) ||
                (u['batch_name'] ?? '').toLowerCase().contains(q);
          }).toList();
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final newVal = !(user['is_active'] as bool? ?? true);
    try {
      await Supabase.instance.client
          .from('web_users')
          .update({'is_active': newVal}).eq('id', user['id']);
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteUser(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除此學員嗎？此操作無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('刪除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('web_users').delete().eq('id', id);
      await _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除失敗：$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openForm({Map<String, dynamic>? user}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserFormModal(user: user),
    );
    if (saved == true) await _loadUsers();
  }

  Future<void> _signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) context.go('/license');
  }

  // ── Stats ──────────────────────────────────────
  int get _total => _users.length;
  int get _active => _users.where((u) {
        if (!(u['is_active'] as bool? ?? true)) return false;
        final ex = u['expires_at'];
        if (ex == null) return false;
        return DateTime.tryParse(ex)?.isAfter(DateTime.now()) ?? false;
      }).length;
  int get _expired => _users.where((u) {
        final ex = u['expires_at'];
        if (ex == null) return false;
        return DateTime.tryParse(ex)?.isBefore(DateTime.now()) ?? false;
      }).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F3460),
        title: const Text('授權管理後台',
            style: TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _loadUsers,
            tooltip: '重新整理',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: _signOut,
            tooltip: '登出',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: Colors.blue.shade700,
        icon: const Icon(Icons.person_add),
        label: const Text('新增學員'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── 統計卡 ──
                _StatsRow(
                    total: _total, active: _active, expired: _expired),

                // ── 搜尋 ──
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '搜尋姓名 / 身分證 / 梯次',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 14),
                      prefixIcon:
                          const Icon(Icons.search, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF16213E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onChanged: (v) =>
                        setState(() {
                          _query = v;
                          _applyFilter();
                        }),
                  ),
                ),

                // ── 學員清單 ──
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text('沒有符合的學員',
                              style: TextStyle(color: Colors.white38)))
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _UserTile(
                                user: _filtered[i],
                                onEdit: () => _openForm(user: _filtered[i]),
                                onToggle: () => _toggleActive(_filtered[i]),
                                onDelete: () => _deleteUser(_filtered[i]['id']),
                              ),
                        ),
                ),
              ],
            ),
    );
  }
}

// ── 統計列 ─────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final int total, active, expired;
  const _StatsRow(
      {required this.total, required this.active, required this.expired});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          _StatCard(label: '總學員', value: '$total', color: Colors.blue),
          const SizedBox(width: 8),
          _StatCard(label: '有效', value: '$active', color: Colors.green),
          const SizedBox(width: 8),
          _StatCard(
              label: '已到期',
              value: '$expired',
              color: Colors.orange),
          const SizedBox(width: 8),
          _StatCard(
              label: '停用',
              value: '${total - active - expired < 0 ? 0 : total - active - expired}',
              color: Colors.grey),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ── 學員 Tile ──────────────────────────────────
class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final VoidCallback onEdit, onToggle, onDelete;
  const _UserTile(
      {required this.user,
      required this.onEdit,
      required this.onToggle,
      required this.onDelete});

  bool get _isActive => user['is_active'] as bool? ?? true;
  bool get _isExpired {
    final ex = user['expires_at'];
    if (ex == null) return false;
    return DateTime.tryParse(ex)?.isBefore(DateTime.now()) ?? false;
  }

  Color get _statusColor {
    if (!_isActive) return Colors.grey;
    if (_isExpired) return Colors.orange;
    return Colors.green;
  }

  String get _statusLabel {
    if (!_isActive) return '停用';
    if (_isExpired) return '已到期';
    return '有效';
  }

  String _formatDate(String? d) {
    if (d == null) return '-';
    final dt = DateTime.tryParse(d);
    if (dt == null) return d;
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _statusColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8, height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
                color: _statusColor, shape: BoxShape.circle),
          ),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(user['name'] ?? '-',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_statusLabel,
                          style: TextStyle(
                              color: _statusColor, fontSize: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${user['national_id'] ?? '-'}  ·  ${user['batch_name'] ?? '-'}',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  '到期：${_formatDate(user['expires_at'])}  ·  登入 ${user['login_count'] ?? 0} 次',
                  style:
                      const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          // Actions
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white38),
            color: const Color(0xFF0F3460),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'toggle') onToggle();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: const [
                  Icon(Icons.edit, size: 16, color: Colors.white70),
                  SizedBox(width: 8),
                  Text('編輯', style: TextStyle(color: Colors.white)),
                ]),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: Row(children: [
                  Icon(_isActive ? Icons.block : Icons.check_circle,
                      size: 16,
                      color: _isActive ? Colors.orange : Colors.green),
                  const SizedBox(width: 8),
                  Text(_isActive ? '停用' : '啟用',
                      style: const TextStyle(color: Colors.white)),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: const [
                  Icon(Icons.delete, size: 16, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('刪除', style: TextStyle(color: Colors.redAccent)),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
