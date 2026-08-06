import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/section.dart';
import '../../providers/section_provider.dart';
import '../../core/services/study_logger.dart';

// ── Section image map provider ────────────────────────────────────────────────
final sectionImagesProvider = FutureProvider<Map<int, String>>((ref) async {
  final raw = await rootBundle.loadString('assets/json/section_images.json');
  final map = json.decode(raw) as Map<String, dynamic>;
  return map.map((k, v) => MapEntry(int.parse(k), v as String));
});

class SectionReadingPage extends ConsumerStatefulWidget {
  final int chapterId;
  final int sectionId;

  const SectionReadingPage({
    super.key,
    required this.chapterId,
    required this.sectionId,
  });

  @override
  ConsumerState<SectionReadingPage> createState() => _SectionReadingPageState();
}

class _SectionReadingPageState extends ConsumerState<SectionReadingPage> {
  double _fontSize = 16.0;
  bool _showToc = false;
  final DateTime _enterTime = DateTime.now(); // 記錄進入時間

  @override
  void dispose() {
    // 離開頁面時記錄閱讀時長
    final seconds = DateTime.now().difference(_enterTime).inSeconds;
    StudyLogger.chapterRead(
      chapterId: widget.chapterId,
      sectionId: widget.sectionId,
      durationSeconds: seconds,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sectionsAsync    = ref.watch(chapterSectionsProvider(widget.chapterId));
    final sectionImagesAsync = ref.watch(sectionImagesProvider);

    return sectionsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('載入失敗: $e'))),
      data: (sections) {
        if (sections.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('教材閱讀')),
            body: const Center(child: Text('無教材內容')),
          );
        }
        final idx       = sections.indexWhere((s) => s.id == widget.sectionId);
        final current   = idx >= 0 ? sections[idx] : sections[0];
        final currentIdx = idx >= 0 ? idx : 0;
        final imageMap  = sectionImagesAsync.valueOrNull ?? {};
        return _buildPage(context, sections, current, currentIdx, imageMap);
      },
    );
  }

  // ── Inline style parser ────────────────────────────────────────────────────
  // ==text== → red + bold     **text** → bold
  static final _markerRe = RegExp(r'==([^=]+)==|\*\*([^*]+)\*\*');

  List<TextSpan> _parseSpans(String text, TextStyle base) {
    final spans = <TextSpan>[];
    int cursor = 0;
    for (final m in _markerRe.allMatches(text)) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: base.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
        ));
      } else {
        spans.add(TextSpan(
          text: m.group(2),
          style: base.copyWith(fontWeight: FontWeight.bold),
        ));
      }
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: base));
    }
    return spans.isEmpty ? [TextSpan(text: text, style: base)] : spans;
  }

  Widget _richText(String text, TextStyle style,
      {TextAlign align = TextAlign.start}) {
    final spans = _parseSpans(text, style);
    if (spans.length == 1 && spans.first.style == style) {
      return Text(text, style: style, textAlign: align);
    }
    return RichText(
      textAlign: align,
      text: TextSpan(children: spans),
      textScaler: MediaQuery.textScalerOf(context),
    );
  }

  // ── Page layout ────────────────────────────────────────────────────────────
  Widget _buildPage(
    BuildContext context,
    List<Section> sections,
    Section current,
    int currentIdx,
    Map<int, String> imageMap,
  ) {
    final imagePath = imageMap[current.id];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          current.title,
          style: const TextStyle(fontSize: 14),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_size),
            onPressed: () => _showFontSizeDialog(context),
            tooltip: '字體大小',
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => setState(() => _showToc = !_showToc),
            tooltip: '目錄',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (currentIdx + 1) / sections.length,
            minHeight: 4,
          ),
        ),
      ),
      body: Row(
        children: [
          // ── TOC sidebar ───────────────────────────────────────────────────
          if (_showToc)
            Container(
              width: 220,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  right: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '本章目錄',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: sections.length,
                      itemBuilder: (_, i) {
                        final s = sections[i];
                        final isActive = s.id == current.id;
                        return InkWell(
                          onTap: () {
                            setState(() => _showToc = false);
                            context.pushReplacement(
                                '/section/${s.chapterId}/${s.id}');
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Theme.of(context)
                                      .colorScheme
                                      .primaryContainer
                                  : null,
                            ),
                            child: Text(
                              '${i + 1}. ${s.title}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isActive
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isActive
                                    ? Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          // ── Main content ──────────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section title
                        Text(
                          current.title,
                          style: TextStyle(
                            fontSize: _fontSize + 4,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Divider(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3)),
                        const SizedBox(height: 16),
                        // Text content
                        _buildRichContent(context, current.content),
                        // ── Section image (below text) ─────────────────────
                        if (imagePath != null) ...[
                          const SizedBox(height: 24),
                          _buildSectionImage(context, imagePath),
                        ],
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
                _buildNavBar(context, sections, currentIdx),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section image widget ───────────────────────────────────────────────────
  Widget _buildSectionImage(BuildContext context, String assetPath) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: Theme.of(context).colorScheme.primary.withOpacity(0.2)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(Icons.image_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.7)),
              const SizedBox(width: 6),
              Text(
                '本節圖解',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => _showFullScreenImage(context, assetPath),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.zoom_in,
                  size: 12, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text('點擊放大',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400])),
            ],
          ),
        ),
      ],
    );
  }

  void _showFullScreenImage(BuildContext context, String assetPath) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('本節圖解',
                style: TextStyle(color: Colors.white)),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Center(
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Content renderer ───────────────────────────────────────────────────────
  Widget _buildRichContent(BuildContext context, String content) {
    final lines = content.split('\n');
    final widgets = <Widget>[];

    for (var line in lines) {
      line = line.trimRight();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (RegExp(r'^[一二三四五六七八九十]+[、．.]').hasMatch(line)) {
        widgets.add(_buildPoint(context, line, level: 0));
      } else if (RegExp(r'^\([一二三四五六七八九十\d]+\)').hasMatch(line)) {
        widgets.add(_buildPoint(context, line, level: 1));
      } else if (RegExp(r'^\d+[\.、\.]').hasMatch(line)) {
        widgets.add(_buildPoint(context, line, level: 1));
      } else if (line.startsWith('※')) {
        widgets.add(_buildNote(context, line));
      } else if (RegExp(r'^第[一二三四五六七八九十]+[節章]').hasMatch(line)) {
        widgets.add(_buildSubheader(context, line));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _richText(
            line,
            TextStyle(
              fontSize: _fontSize,
              height: 1.8,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildPoint(BuildContext context, String line, {required int level}) {
    final style = TextStyle(
      fontSize: _fontSize,
      height: 1.7,
      fontWeight: level == 0 ? FontWeight.w500 : FontWeight.normal,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Padding(
      padding: EdgeInsets.only(
          left: level * 16.0, bottom: 6, top: level == 0 ? 4 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (level == 0)
            Container(
              margin: const EdgeInsets.only(top: 6, right: 8),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Icon(Icons.arrow_right,
                  size: 16,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.6)),
            ),
          Expanded(child: _richText(line, style)),
        ],
      ),
    );
  }

  Widget _buildNote(BuildContext context, String line) {
    final style = TextStyle(
      fontSize: _fontSize - 1,
      height: 1.6,
      color: Theme.of(context).colorScheme.onTertiaryContainer,
      fontStyle: FontStyle.italic,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .tertiaryContainer
            .withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: Theme.of(context).colorScheme.tertiary,
            width: 3,
          ),
        ),
      ),
      child: _richText(line, style),
    );
  }

  Widget _buildSubheader(BuildContext context, String line) {
    final style = TextStyle(
      fontSize: _fontSize + 1,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).colorScheme.secondary,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: _richText(line, style),
    );
  }

  // ── Navigation bar ─────────────────────────────────────────────────────────
  Widget _buildNavBar(
      BuildContext context, List<Section> sections, int currentIdx) {
    final hasPrev = currentIdx > 0;
    final hasNext = currentIdx < sections.length - 1;
    final isLast = !hasNext;
    final chapterId = sections[currentIdx].chapterId;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '第 ${currentIdx + 1} 節 / 共 ${sections.length} 節',
              style: TextStyle(color: Colors.grey[500], fontSize: 11),
            ),
            const SizedBox(height: 6),
            // ── 最後一節：3 按鈕版本 ───────────────────────────────────
            if (isLast)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasPrev
                          ? () {
                              final prev = sections[currentIdx - 1];
                              context.pushReplacement(
                                  '/section/${prev.chapterId}/${prev.id}');
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back, size: 15),
                      label: const Text('上一節',
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 本章測驗（只在最後一節）
                  FilledButton.icon(
                    onPressed: () => context.push('/quiz/$chapterId'),
                    icon: const Icon(Icons.quiz_outlined, size: 15),
                    label: const Text('本章測驗',
                        style: TextStyle(fontSize: 13)),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.secondary,
                      foregroundColor:
                          Theme.of(context).colorScheme.onSecondary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.check, size: 15),
                      label: const Text('完成閱讀',
                          style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 10),
                      ),
                    ),
                  ),
                ],
              )
            else
              // ── 非最後一節：2 按鈕版本 ────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasPrev
                          ? () {
                              final prev = sections[currentIdx - 1];
                              context.pushReplacement(
                                  '/section/${prev.chapterId}/${prev.id}');
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: const Text('上一節'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final next = sections[currentIdx + 1];
                        context.pushReplacement(
                            '/section/${next.chapterId}/${next.id}');
                      },
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text('下一節'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Font size dialog ───────────────────────────────────────────────────────
  void _showFontSizeDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('字體大小',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.text_fields),
                  Expanded(
                    child: Slider(
                      value: _fontSize,
                      min: 13,
                      max: 22,
                      divisions: 9,
                      label: '${_fontSize.toInt()} pt',
                      onChanged: (v) {
                        setS(() {});
                        setState(() => _fontSize = v);
                      },
                    ),
                  ),
                  const Icon(Icons.text_fields, size: 28),
                ],
              ),
              Text(
                '預覽：人身保險是保障生活品質的基石。',
                style: TextStyle(fontSize: _fontSize),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
