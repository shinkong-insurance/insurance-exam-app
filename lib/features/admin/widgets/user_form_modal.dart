// lib/features/admin/widgets/user_form_modal.dart
// 新增 / 編輯學員彈窗

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserFormModal extends StatefulWidget {
  final Map<String, dynamic>? user; // null = 新增

  const UserFormModal({super.key, this.user});

  @override
  State<UserFormModal> createState() => _UserFormModalState();
}

class _UserFormModalState extends State<UserFormModal> {
  final _nameCtrl = TextEditingController();
  final _idCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isActive = true;
  bool _loading = false;
  String? _error;

  // birth_date
  int? _bYear;
  int? _bMonth;
  int? _bDay;

  // expires_at
  DateTime _expires = DateTime.now().add(const Duration(days: 90));

  bool get _isEdit => widget.user != null;

  static const int _minYear = 1940;
  static final int _maxYear = DateTime.now().year - 15;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    if (u != null) {
      _nameCtrl.text = u['name'] ?? '';
      _idCtrl.text = u['national_id'] ?? '';
      _batchCtrl.text = u['batch_name'] ?? '';
      _notesCtrl.text = u['notes'] ?? '';
      _isActive = u['is_active'] as bool? ?? true;
      // parse birth_date
      final bd = u['birth_date'] as String?;
      if (bd != null) {
        final parts = bd.split('-');
        if (parts.length == 3) {
          _bYear = int.tryParse(parts[0]);
          _bMonth = int.tryParse(parts[1]);
          _bDay = int.tryParse(parts[2]);
        }
      }
      // parse expires_at
      final ex = u['expires_at'] as String?;
      if (ex != null) {
        _expires = DateTime.tryParse(ex) ?? _expires;
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _batchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _buildBirthDate() {
    if (_bYear == null || _bMonth == null || _bDay == null) return null;
    return '$_bYear-${_bMonth.toString().padLeft(2, '0')}-${_bDay.toString().padLeft(2, '0')}';
  }

  bool _validateId(String id) =>
      id.length == 10 && RegExp(r'^[A-Z][12][0-9]{8}$').hasMatch(id);

  int _daysInMonth(int y, int m) => DateUtils.getDaysInMonth(y, m);

  Future<void> _pickExpiresDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expires,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expires = picked);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final id = _idCtrl.text.trim().toUpperCase();
    final batch = _batchCtrl.text.trim();
    final birthDate = _buildBirthDate();

    if (name.isEmpty) {
      setState(() => _error = '請輸入姓名');
      return;
    }
    if (!_validateId(id)) {
      setState(() => _error = '身分證號碼格式不正確');
      return;
    }
    if (birthDate == null) {
      setState(() => _error = '請選擇出生年月日');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final payload = {
        'name': name,
        'national_id': id,
        'birth_date': birthDate,
        'batch_name': batch.isEmpty ? '一般學員' : batch,
        'expires_at':
            '${_expires.year}-${_expires.month.toString().padLeft(2, '0')}-${_expires.day.toString().padLeft(2, '0')}',
        'is_active': _isActive,
        'notes': _notesCtrl.text.trim(),
      };

      if (_isEdit) {
        await Supabase.instance.client
            .from('web_users')
            .update(payload)
            .eq('id', widget.user!['id']);
      } else {
        await Supabase.instance.client.from('web_users').insert(payload);
      }

      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.code == '23505' ? '此身分證號碼已存在' : '儲存失敗：${e.message}';
      });
    } catch (e) {
      setState(() => _error = '儲存失敗：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F3460),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(_isEdit ? Icons.edit : Icons.person_add,
                      color: Colors.blue.shade300),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? '編輯學員資料' : '新增學員',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            // Form
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _label('姓名 *'),
                  _textField(controller: _nameCtrl, hint: '學員姓名'),
                  const SizedBox(height: 12),

                  _label('身分證號碼 *'),
                  _textField(
                    controller: _idCtrl,
                    hint: 'A123456789',
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                      LengthLimitingTextInputFormatter(10),
                      _Upper(),
                    ],
                    style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        letterSpacing: 2),
                    readOnly: _isEdit,
                  ),
                  const SizedBox(height: 12),

                  _label('出生年月日 *'),
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: _dropdown<int>(
                        hint: '年',
                        value: _bYear,
                        items: List.generate(
                            _maxYear - _minYear + 1, (i) => _maxYear - i),
                        label: (v) => '$v',
                        onChanged: (v) =>
                            setState(() {
                              _bYear = v;
                              _bDay = null;
                            }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _dropdown<int>(
                        hint: '月',
                        value: _bMonth,
                        items: List.generate(12, (i) => i + 1),
                        label: (v) => '$v',
                        onChanged: (v) =>
                            setState(() {
                              _bMonth = v;
                              _bDay = null;
                            }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _dropdown<int>(
                        hint: '日',
                        value: _bDay,
                        items: List.generate(
                          (_bYear != null && _bMonth != null)
                              ? _daysInMonth(_bYear!, _bMonth!)
                              : 31,
                          (i) => i + 1,
                        ),
                        label: (v) => '$v',
                        onChanged: (v) => setState(() => _bDay = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  _label('梯次 / 班別'),
                  _textField(controller: _batchCtrl, hint: '例：2026年7月班'),
                  const SizedBox(height: 12),

                  _label('到期日 *'),
                  GestureDetector(
                    onTap: _pickExpiresDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16213E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            color: Colors.white38, size: 18),
                        const SizedBox(width: 10),
                        Text(
                          '${_expires.year}/${_expires.month.toString().padLeft(2, '0')}/${_expires.day.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _label('備註'),
                  _textField(
                      controller: _notesCtrl,
                      hint: '選填',
                      maxLines: 2),
                  const SizedBox(height: 12),

                  // Active toggle
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16213E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('啟用授權',
                            style: TextStyle(color: Colors.white70)),
                        Switch(
                          value: _isActive,
                          onChanged: (v) => setState(() => _isActive = v),
                          activeColor: Colors.green,
                        ),
                      ],
                    ),
                  ),

                  // Error
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 13)),
                    ),
                  ],

                  const SizedBox(height: 24),
                  SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : Text(_isEdit ? '儲存修改' : '新增學員',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: const TextStyle(color: Colors.white60, fontSize: 12)),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    List<TextInputFormatter>? formatters,
    TextStyle? style,
    bool readOnly = false,
    int maxLines = 1,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: readOnly
              ? const Color(0xFF0A1525)
              : const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: TextField(
          controller: controller,
          inputFormatters: formatters,
          style: style ?? const TextStyle(color: Colors.white),
          maxLines: maxLines,
          readOnly: readOnly,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      );

  Widget _dropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    required void Function(T?)? onChanged,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: DropdownButton<T>(
          value: value,
          hint:
              Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          dropdownColor: const Color(0xFF16213E),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          underline: const SizedBox(),
          isExpanded: true,
          onChanged: onChanged,
          items: items
              .map((v) => DropdownMenuItem(value: v, child: Text(label(v))))
              .toList(),
        ),
      );
}

class _Upper extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue o, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}
