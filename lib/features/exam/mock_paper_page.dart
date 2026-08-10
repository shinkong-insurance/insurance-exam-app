import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class MockPaperPage extends StatefulWidget {
  const MockPaperPage({super.key});

  @override
  State<MockPaperPage> createState() => _MockPaperPageState();
}

class _MockPaperPageState extends State<MockPaperPage> {
  final Map<String, bool> _loading = {};

  static const _shiWuPapers = [
    {'name': '模擬卷_實務A', 'label': '實務 A 卷'},
    {'name': '模擬卷_實務B', 'label': '實務 B 卷'},
    {'name': '模擬卷_實務C', 'label': '實務 C 卷'},
  ];

  static const _faGuiPapers = [
    {'name': '模擬卷_法規A', 'label': '法規 A 卷'},
    {'name': '模擬卷_法規B', 'label': '法規 B 卷'},
    {'name': '模擬卷_法規C', 'label': '法規 C 卷'},
  ];

  Future<void> _openPdf(String assetName) async {
    // Web 平台不支援 path_provider / open_file，顯示說明訊息
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web 版暫不支援直接開啟 PDF，請使用 Android App 版本'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _loading[assetName] = true);
    try {
      final byteData = await rootBundle.load('assets/guides/$assetName.pdf');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$assetName.pdf');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法開啟 PDF：${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading[assetName] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('練習考卷')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SubjectSection(
            title: '保險實務',
            color: const Color(0xFF1565C0),
            icon: Icons.work_outline,
            papers: _shiWuPapers,
            loading: _loading,
            onOpen: _openPdf,
          ),
          const SizedBox(height: 16),
          _SubjectSection(
            title: '保險法規',
            color: Colors.indigo,
            icon: Icons.gavel_outlined,
            papers: _faGuiPapers,
            loading: _loading,
            onOpen: _openPdf,
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              '點擊卷別即可開啟 PDF 閱覽',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectSection extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<Map<String, String>> papers;
  final Map<String, bool> loading;
  final void Function(String) onOpen;

  const _SubjectSection({
    required this.title,
    required this.color,
    required this.icon,
    required this.papers,
    required this.loading,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ...papers.map((p) {
          final name = p['name']!;
          final label = p['label']!;
          final isLoading = loading[name] == true;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.1),
                child: Icon(Icons.picture_as_pdf, color: color),
              ),
              title: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('點擊開啟 PDF',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              trailing: isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.open_in_new, color: color),
              onTap: isLoading ? null : () => onOpen(name),
            ),
          );
        }),
      ],
    );
  }
}
