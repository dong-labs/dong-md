import 'dart:io';
import 'about_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

void main() {
  runApp(const SparrowApp());
}

/// 文件类型枚举
enum FileType {
  markdown,
  html,
  json,
  plainText,
}

/// 文件类型检测工具
class FileDetector {
  /// 根据扩展名判断文件类型
  static FileType detectByExtension(String fileName) {
    final ext = fileName.toLowerCase();

    // Markdown 文件
    if (ext.endsWith('.md') ||
        ext.endsWith('.markdown') ||
        ext.endsWith('.mdown') ||
        ext.endsWith('.mkd')) {
      return FileType.markdown;
    }

    // HTML 文件
    if (ext.endsWith('.html') || ext.endsWith('.htm')) {
      return FileType.html;
    }

    // JSON 文件
    if (ext.endsWith('.json')) {
      return FileType.json;
    }

    // 纯文本
    return FileType.plainText;
  }

  /// 根据内容检测文件类型
  static FileType detectByContent(String content) {
    final trimmed = content.trim();

    // 检测 HTML
    if (_isHtml(trimmed)) {
      return FileType.html;
    }

    // 检测 JSON
    if (_isJson(trimmed)) {
      return FileType.json;
    }

    // 检测 Markdown
    if (_isMarkdown(trimmed)) {
      return FileType.markdown;
    }

    // 默认纯文本
    return FileType.plainText;
  }

  /// 混合检测（扩展名 + 内容）
  static FileType detect(String fileName, String content) {
    // 先检查扩展名
    final extType = detectByExtension(fileName);

    // 如果是明确的类型，直接返回
    if (extType == FileType.markdown ||
        extType == FileType.html ||
        extType == FileType.json) {
      return extType;
    }

    // .txt 或未知扩展名，检查内容
    return detectByContent(content);
  }

  /// 检测是否为 HTML
  static bool _isHtml(String content) {
    final htmlPattern = RegExp(
      r'<(html|body|div|p|span|h1|h2|h3|ul|ol|li|table|form|input|script|style|meta|link)\b',
      caseSensitive: false,
    );
    return htmlPattern.hasMatch(content);
  }

  /// 检测是否为 JSON
  static bool _isJson(String content) {
    if (!content.startsWith('{') && !content.startsWith('[')) {
      return false;
    }
    try {
      jsonDecode(content);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 检测是否为 Markdown
  static bool _isMarkdown(String content) {
    int score = 0;

    // 标题标记
    if (RegExp(r'^#{1,6}\s', multiLine: true).hasMatch(content)) score += 3;

    // 粗体/斜体
    if (RegExp(r'\*\*.*?\*\*|__.*?__').hasMatch(content)) score += 2;
    if (RegExp(r'\*.*?\*|_.*?_').hasMatch(content)) score += 1;

    // 链接
    if (RegExp(r'\[.*?\]\(.*?\)').hasMatch(content)) score += 3;

    // 代码块
    if (RegExp(r'```[\s\S]*?```').hasMatch(content)) score += 3;
    if (RegExp(r'`[^`]+`').hasMatch(content)) score += 1;

    // 列表
    if (RegExp(r'^\s*[-*+]\s', multiLine: true).hasMatch(content)) score += 2;
    if (RegExp(r'^\s*\d+\.\s', multiLine: true).hasMatch(content)) score += 2;

    // 引用
    if (RegExp(r'^>\s', multiLine: true).hasMatch(content)) score += 2;

    // 表格
    if (RegExp(r'\|.*\|').hasMatch(content)) score += 2;

    // 如果得分 >= 3，认为是 Markdown
    return score >= 3;
  }

  /// 获取文件类型显示名称
  static String getFileTypeName(FileType type) {
    switch (type) {
      case FileType.markdown:
        return 'Markdown';
      case FileType.html:
        return 'HTML';
      case FileType.json:
        return 'JSON';
      case FileType.plainText:
        return '纯文本';
    }
  }

  /// 获取文件类型图标
  static IconData getFileTypeIcon(FileType type) {
    switch (type) {
      case FileType.markdown:
        return Icons.description;
      case FileType.html:
        return Icons.web;
      case FileType.json:
        return Icons.code;
      case FileType.plainText:
        return Icons.text_snippet;
    }
  }
}

class SparrowApp extends StatelessWidget {
  const SparrowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '麻雀MD',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4078F0),
      ),
      home: const HomeScreen(),
    );
  }
}

class FileRecord {
  final String id;
  final String fileName;
  final String localPath;
  final DateTime openedAt;

  /// 内容指纹，用于历史去重（同一文件反复打开只保留一条并置顶）。
  final String contentHash;

  /// 字数与文件大小，导入时计算一次后随元数据持久化，列表展示无需再做磁盘 IO。
  final int wordCount;
  final int fileSize;

  FileRecord({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.openedAt,
    required this.contentHash,
    required this.wordCount,
    required this.fileSize,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'localPath': localPath,
    'openedAt': openedAt.toIso8601String(),
    'contentHash': contentHash,
    'wordCount': wordCount,
    'fileSize': fileSize,
    // content 不再持久化（文件本身已在 dong-md/files/ 下，避免 SP 膨胀）。
  };

  factory FileRecord.fromJson(Map<String, dynamic> json) {
    // 老版本数据兼容：旧 JSON 可能带 content 字段（这里忽略，元数据已够用），
    // 旧数据缺 contentHash/wordCount/fileSize 时给安全默认值，运行后会被重新持久化。
    return FileRecord(
      id: json['id'] ?? '',
      fileName: json['fileName'] ?? '',
      localPath: json['localPath'] ?? '',
      openedAt: json['openedAt'] != null
          ? DateTime.parse(json['openedAt'])
          : DateTime.now(),
      contentHash: json['contentHash'] as String? ?? '',
      wordCount: json['wordCount'] as int? ?? 0,
      fileSize: json['fileSize'] as int? ??
          FileManager.getFileSizeSync(json['localPath'] ?? ''),
    );
  }

  FileRecord copyWith({
    String? fileName,
    String? localPath,
    DateTime? openedAt,
    int? fileSize,
  }) {
    return FileRecord(
      id: id,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      openedAt: openedAt ?? this.openedAt,
      contentHash: contentHash,
      wordCount: wordCount,
      fileSize: fileSize ?? this.fileSize,
    );
  }
}

/// 计算内容指纹。不引入额外依赖，用字符串 hashCode（去重场景足够，
/// 碰撞概率极低且后果仅为多保留一条记录，不影响数据正确性）。
String contentHashOf(String content) => 'h${content.hashCode}';

/// 字数统计：去除 Markdown 常见语法符号后的可见字符数，
/// 比纯 content.length 更接近真实阅读量。
int countWordsOf(String content) {
  final cleaned = content
      .replaceAll(RegExp(r'```[\s\S]*?```'), '') // 代码块
      .replaceAll(RegExp(r'`[^`]*`'), '') // 行内代码
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // 图片
      .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1') // 链接保留文字
      .replaceAll(RegExp(r'[#>*_~\-]'), '') // 语法符号
      .replaceAll(RegExp(r'\s+'), '');
  return cleaned.length;
}

/// 新建笔记的默认文件名：按时间生成，避免与已有文件冲突。
String defaultNoteName() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '笔记-${two(now.month)}${two(now.day)} ${two(now.hour)}${two(now.minute)}.md';
}

class FileManager {
  static Future<String> saveFile(String fileName, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final mdDir = Directory('${dir.path}/dong-md/files');
    await mdDir.create(recursive: true);

    String targetName = fileName;
    String targetPath = '${mdDir.path}/$targetName';

    if (File(targetPath).existsSync()) {
      final existingContent = File(targetPath).readAsStringSync();
      if (existingContent == content) {
        return targetPath;
      }

      int counter = 1;
      final baseName = fileName.endsWith('.md')
          ? fileName.substring(0, fileName.length - 3)
          : fileName;

      while (true) {
        targetName = '${baseName}_$counter.md';
        targetPath = '${mdDir.path}/$targetName';
        if (!File(targetPath).existsSync()) break;

        final existing = File(targetPath).readAsStringSync();
        if (existing == content) {
          return targetPath;
        }
        counter++;
      }
    }

    await File(targetPath).writeAsString(content);
    return targetPath;
  }

  /// 编辑保存：直接覆盖写回原文件。
  /// 不走 saveFile（那是导入语义，同路径不同内容会另存 _1.md 副本，
  /// 用于编辑会把同一次笔记越存越多）。
  static Future<void> updateFile(String localPath, String content) async {
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('文件不存在', localPath);
    }
    await file.writeAsString(content);
  }

  static Future<String> renameFile(String oldPath, String newFileName) async {
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) return oldPath;

    final dir = await getApplicationDocumentsDirectory();
    final mdDir = Directory('${dir.path}/dong-md/files');

    String newPath = '${mdDir.path}/$newFileName';

    // 如果目标文件已存在，添加后缀
    if (File(newPath).existsSync()) {
      final baseName = newFileName.endsWith('.md')
          ? newFileName.substring(0, newFileName.length - 3)
          : newFileName;
      int counter = 1;
      while (File('${mdDir.path}/${baseName}_$counter.md').existsSync()) {
        counter++;
      }
      newPath = '${mdDir.path}/${baseName}_$counter.md';
    }

    await oldFile.rename(newPath);
    return newPath;
  }

  static Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  /// 同步获取文件大小，仅在老数据迁移（fromJson 兜底）时使用，不在列表渲染热路径调用。
  static int getFileSizeSync(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) return file.lengthSync();
    } catch (_) {}
    return 0;
  }

  /// 懒加载：打开历史项时从磁盘重新读取内容，避免在 SP 里冗余存全文。
  static Future<String> readFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// 历史排序方式，选择持久化到 SharedPreferences。
enum HistorySort { recent, name, size }

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.gudong.sparrow/file');

  List<FileRecord> _history = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  HistorySort _sort = HistorySort.recent;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _consumeLaunchContent();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('file_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(historyJson);
    final loaded = decoded.map((e) => FileRecord.fromJson(e)).toList();

    // 老数据兼容：旧版本把 content 全量存进 SP，且缺 contentHash/wordCount/fileSize。
    // 这里检测到旧格式（任意一条带 content 或缺 contentHash）就重新持久化瘦身，
    // 一次性迁移，之后不再触发。
    final needsMigration = loaded.isEmpty
        ? false
        : decoded.any((e) =>
            (e is Map && e.containsKey('content')) ||
            (e is Map && (e['contentHash'] == null || e['contentHash'] == '')));

    // 读取排序偏好
    final sortIndex = prefs.getInt('history_sort') ?? 0;
    final sort = HistorySort.values[sortIndex.clamp(0, HistorySort.values.length - 1)];

    setState(() {
      _history = loaded;
      _sort = sort;
      _isLoading = false;
    });

    if (needsMigration) {
      await _saveHistory();
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    await prefs.setString('file_history', historyJson);
  }

  Future<void> _saveSort() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('history_sort', _sort.index);
  }

  Future<FileRecord> _addFileToHistory(String fileName, String content) async {
    final localPath = await FileManager.saveFile(fileName, content);
    final hash = contentHashOf(content);
    final now = DateTime.now();
    final wordCount = countWordsOf(content);
    final fileSize = await FileManager.getFileSize(localPath);

    // 去重 + 置顶：命中相同内容指纹的旧记录，更新其时间/大小并移到列表头部。
    final existingIndex =
        _history.indexWhere((r) => r.contentHash == hash);
    if (existingIndex >= 0) {
      final old = _history.removeAt(existingIndex);
      final updated = old.copyWith(openedAt: now, fileSize: fileSize);
      setState(() {
        _history.insert(0, updated);
      });
      await _saveHistory();
      return updated;
    }

    final record = FileRecord(
      id: now.millisecondsSinceEpoch.toString(),
      fileName: fileName,
      localPath: localPath,
      openedAt: now,
      contentHash: hash,
      wordCount: wordCount,
      fileSize: fileSize,
    );
    setState(() {
      _history.insert(0, record);
    });
    await _saveHistory();
    return record;
  }

  /// 启动时（含从分享/打开方式冷启动）主动拉取原生缓存的文件内容。
  /// 配合 MainActivity 的 consumeLaunchContent，一次性取走并清空，
  /// 冷热启动都走这条路径，避免旧实现里 Flutter handler 未就绪丢内容的问题。
  Future<void> _consumeLaunchContent() async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<dynamic>('consumeLaunchContent');
    } on PlatformException {
      return;
    }
    if (raw is! Map) return;
    final result = Map<String, dynamic>.from(raw);

    final path = result['path'] as String?;
    final content = result['content'] as String?;
    if (content == null) return;

    final fileName = path?.split('/').last ?? '未命名.md';

    // _addFileToHistory 内部已落盘，复用其返回的 localPath，不再重复 saveFile。
    final record = await _addFileToHistory(fileName, content);

    // 检测文件类型
    final fileType = FileDetector.detect(fileName, content);

    if (mounted) {
      // 显示文件类型提示
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(FileDetector.getFileTypeIcon(fileType),
                  color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text('正在打开 ${FileDetector.getFileTypeName(fileType)} 文件...'),
            ],
          ),
          duration: const Duration(seconds: 1),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReaderScreen(
            fileName: record.fileName,
            content: content,
            localPath: record.localPath,
            fileType: fileType,
          ),
        ),
      );
    }
  }

  List<FileRecord> get _filteredHistory {
    var list = _searchQuery.isEmpty
        ? List<FileRecord>.from(_history)
        : _history
            .where((record) =>
                record.fileName.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList();

    switch (_sort) {
      case HistorySort.recent:
        list.sort((a, b) => b.openedAt.compareTo(a.openedAt));
        break;
      case HistorySort.name:
        list.sort((a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()));
        break;
      case HistorySort.size:
        list.sort((a, b) => b.fileSize.compareTo(a.fileSize));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索文件...',
                border: InputBorder.none,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            )
          : const Text('麻雀MD'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          // 排序：仅在非搜索态显示，避免抢搜索输入的焦点。
          if (!_isSearching && _history.isNotEmpty)
            PopupMenuButton<HistorySort>(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onSelected: (value) {
                setState(() => _sort = value);
                _saveSort();
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: HistorySort.recent,
                  checked: _sort == HistorySort.recent,
                  child: const Text('最近打开'),
                ),
                CheckedPopupMenuItem(
                  value: HistorySort.name,
                  checked: _sort == HistorySort.name,
                  child: const Text('文件名'),
                ),
                CheckedPopupMenuItem(
                  value: HistorySort.size,
                  checked: _sort == HistorySort.size,
                  child: const Text('文件大小'),
                ),
              ],
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'about') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('关于'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        tooltip: '新建笔记',
        onPressed: _createNote,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_history.isEmpty) {
      return _buildEmptyState();
    }

    final filtered = _filteredHistory;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '未找到 "$_searchQuery"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final record = filtered[index];
        return _buildHistoryItem(record, index);
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo（麻雀品牌图标）
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),

            const SizedBox(height: 24),

            // 标题
            const Text(
              '麻雀MD',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Slogan
            Text(
              '随身阅读任意文本文件',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 20),

            // 用法说明
            Text(
              '在微信、文件管理器或其他应用里收到 Markdown、日志、代码等文本文件时，'
              '选择用麻雀MD 打开，即可获得清爽舒适的阅读体验。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                height: 1.6,
              ),
            ),

            const SizedBox(height: 24),

            // 打开示例文档
            FilledButton.icon(
              onPressed: _openDemo,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('打开示例文档'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              ),
            ),

            const SizedBox(height: 32),

            // 功能说明卡片
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      Icons.share_outlined,
                      '从其他应用打开',
                      '微信 / 文件管理器里点「打开方式」或「分享」',
                    ),
                    const Divider(),
                    _buildFeatureItem(
                      Icons.folder_open_outlined,
                      '支持任意文本文件',
                      '.md / .txt / .log / .json / .csv ...',
                    ),
                    const Divider(),
                    _buildFeatureItem(
                      Icons.auto_awesome_outlined,
                      '优质排版',
                      '自动渲染表格、代码高亮、Mermaid 流程图',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开内置示例文档：让用户首次进入就能直观看到 Markdown 渲染效果，
  /// 同时也是一份「怎么用」的引导。示例会入历史，方便下次再看。
  Future<void> _openDemo() async {
    const fileName = '示例文档.md';
    const content = _kDemoMarkdown;
    final record = await _addFileToHistory(fileName, content);
    final fileType = FileDetector.detect(fileName, content);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          fileName: record.fileName,
          content: content,
          localPath: record.localPath,
          fileType: fileType,
        ),
      ),
    );
    if (mounted) _loadHistory();
  }

  /// 新建笔记：先进编辑器，保存（由 EditorScreen 写文件 + 入历史）后刷新列表。
  Future<void> _createNote() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(
          fileName: defaultNoteName(),
          initialContent: '',
          localPath: null,
        ),
      ),
    );
    if (saved == true && mounted) {
      _loadHistory();
    }
  }

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
    );
  }

  Widget _buildHistoryItem(FileRecord record, int index) {
    // 不再每次 build 同步读磁盘；fileSize/wordCount 在导入时已随元数据缓存。
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.description, color: Colors.orange),
      ),
      title: Text(
        record.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_formatDate(record.openedAt)} · ${_formatFileSize(record.fileSize)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '${record.wordCount} 字',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => _handleMenuAction(value, record, index),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'open',
            child: ListTile(
              leading: Icon(Icons.open_in_new),
              title: Text('打开'),
            ),
          ),
          const PopupMenuItem(
            value: 'rename',
            child: ListTile(
              leading: Icon(Icons.edit),
              title: Text('重命名'),
            ),
          ),
          const PopupMenuItem(
            value: 'share_content',
            child: ListTile(
              leading: Icon(Icons.text_fields),
              title: Text('分享内容'),
            ),
          ),
          const PopupMenuItem(
            value: 'share_file',
            child: ListTile(
              leading: Icon(Icons.insert_drive_file),
              title: Text('分享文件'),
            ),
          ),
          const PopupMenuItem(
            value: 'detail',
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('文件详情'),
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ),
        ],
      ),
      onTap: () => _openRecord(record),
    );
  }

  /// 打开历史记录：从磁盘懒加载内容后进入阅读页。文件不存在时给出提示。
  Future<void> _openRecord(FileRecord record) async {
    final content = await FileManager.readFile(record.localPath);
    if (!mounted) return;
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已不存在，请重新导入')),
      );
      return;
    }

    // 检测文件类型
    final fileType = FileDetector.detect(record.fileName, content);

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReaderScreen(
          fileName: record.fileName,
          content: content,
          localPath: record.localPath,
          fileType: fileType,
        ),
      ),
    );
    // 阅读页内可能编辑保存过（SP 历史已被 EditorScreen 更新），回来重载列表。
    if (mounted) _loadHistory();
  }

  void _handleMenuAction(String action, FileRecord record, int index) {
    switch (action) {
      case 'open':
        _openRecord(record);
        break;
      case 'rename':
        _showRenameDialog(record, index);
        break;
      case 'share_content':
        _shareContent(record);
        break;
      case 'share_file':
        Share.shareXFiles(
          [XFile(record.localPath)],
          subject: record.fileName,
        );
        break;
      case 'detail':
        _openDetail(record);
        break;
      case 'delete':
        _showDeleteDialog(record);
        break;
    }
  }

  /// 分享内容：从磁盘懒加载后分享。
  Future<void> _shareContent(FileRecord record) async {
    final content = await FileManager.readFile(record.localPath);
    if (content.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('文件已不存在，请重新导入')),
      );
      return;
    }
    Share.share(content, subject: record.fileName);
  }

  /// 打开文件详情：从磁盘懒加载内容后进入。
  Future<void> _openDetail(FileRecord record) async {
    final content = await FileManager.readFile(record.localPath);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileDetailScreen(
          fileName: record.fileName,
          localPath: record.localPath,
          content: content,
          onDelete: () {
            setState(() {
              _history.removeWhere((r) => r.id == record.id);
            });
            _saveHistory();
          },
        ),
      ),
    );
  }

  void _showRenameDialog(FileRecord record, int index) {
    final controller = TextEditingController(text: record.fileName);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入文件名',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == record.fileName) {
                Navigator.pop(context);
                return;
              }

              // 确保文件名有 .md 后缀
              final finalName = newName.endsWith('.md') ? newName : '$newName.md';

              // 重命名文件
              final newPath = await FileManager.renameFile(record.localPath, finalName);

              // 更新记录
              setState(() {
                _history[index] = record.copyWith(
                  fileName: finalName,
                  localPath: newPath,
                );
              });
              await _saveHistory();

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已重命名')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(FileRecord record) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「${record.fileName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              await FileManager.deleteFile(record.localPath);
              setState(() {
                _history.removeWhere((r) => r.id == record.id);
              });
              await _saveHistory();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已删除')),
                );
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return '今天 ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else if (date.year == now.year) {
      return '${date.month}-${date.day}';
    } else {
      // 跨年补上年份，避免去年/更早的文件看不出年代。
      return '${date.year}-${date.month}-${date.day}';
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ReaderScreen extends StatefulWidget {
  final String fileName;
  final String content;
  final String localPath;
  final FileType fileType;

  const ReaderScreen({
    super.key,
    required this.fileName,
    required this.content,
    required this.localPath,
    this.fileType = FileType.markdown,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final WebViewController _controller;

  // 正文放在 state 里：编辑保存返回后可就地刷新，无需重建页面。
  late String _content = widget.content;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            if (request.url.startsWith('http://') ||
                request.url.startsWith('https://')) {
              launchUrl(Uri.parse(request.url));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          // 页面加载完成后注入内容。此前用 hash '#reader-ready' 作为就绪信号，
          // 但 hash 变化不构成一次导航、不触发 onNavigationRequest，注入从未执行，
          // 页面空白。onPageFinished 是 WebView 标准的「DOM + 脚本就绪」时机。
          onPageFinished: (String url) {
            debugPrint('[sparrow] onPageFinished: $url');
            _injectContent();
          },
        ),
      )
      ..loadFlutterAsset('assets/web/reader.html');
  }

  /// 通过 JS 调用 HTML 内的 setMarkdown 注入正文。
  /// 用 jsonEncode 转义，任何字符（含 `</script>`、反引号、$）都作为合法 JS
  /// 字符串字面量传递，彻底规避 HTML 解析层面的注入风险。
  void _injectContent() {
    final encodedContent = jsonEncode(_content);
    debugPrint('[sparrow] inject: len=${_content.length}');
    _controller.runJavaScript('window.setMarkdown($encodedContent);').then((_) {
      // 注入后回读 DOM，确认内容真的渲染上去了
      return _controller.runJavaScriptReturningResult(
        'document.getElementById("content").innerHTML.length',
      );
    }).then((len) {
      debugPrint('[sparrow] injected, dom html length = $len');
    }).catchError((e) {
      debugPrint('[sparrow] inject failed: $e');
    });
  }

  /// 跳编辑页；保存返回后就地刷新正文（重读磁盘 + 重新注入 WebView）。
  Future<void> _editContent() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => EditorScreen(
          fileName: widget.fileName,
          initialContent: _content,
          localPath: widget.localPath,
        ),
      ),
    );
    if (saved == true && mounted) {
      // 从磁盘重读，保证与保存内容一致
      final fresh = await File(widget.localPath).readAsString();
      setState(() => _content = fresh);
      _injectContent();
    }
  }

  void _copyMarkdown() {
    Clipboard.setData(ClipboardData(text: _content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Markdown 已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(FileDetector.getFileTypeIcon(widget.fileType), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.fileName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.share),
            onSelected: (value) {
              if (value == 'content') {
                Share.share(_content, subject: widget.fileName);
              } else if (value == 'file') {
                Share.shareXFiles(
                  [XFile(widget.localPath)],
                  subject: widget.fileName,
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'content',
                child: ListTile(
                  leading: Icon(Icons.text_fields),
                  title: Text('分享内容'),
                ),
              ),
              const PopupMenuItem(
                value: 'file',
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file),
                  title: Text('分享文件'),
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'edit') {
                _editContent();
              } else if (value == 'copy') {
                _copyMarkdown();
              } else if (value == 'detail') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FileDetailScreen(
                      fileName: widget.fileName,
                      localPath: widget.localPath,
                      content: _content,
                    ),
                  ),
                );
              } else if (value == 'about') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('编辑'),
                ),
              ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy_outlined),
                  title: Text('复制 Markdown'),
                ),
              ),
              const PopupMenuItem(
                value: 'detail',
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('文件详情'),
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: ListTile(
                  leading: Icon(Icons.info),
                  title: Text('关于'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}

/// 编辑/新建笔记：Markdown 源码编辑。
/// 保存后 pop(true)，调用方据此刷新（ReaderScreen 刷新正文，HomeScreen 重载历史）。
/// localPath 为 null 表示新建。
class EditorScreen extends StatefulWidget {
  final String fileName;
  final String initialContent;
  final String? localPath;

  const EditorScreen({
    super.key,
    required this.fileName,
    required this.initialContent,
    this.localPath,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _saved = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _dirty => _controller.text != widget.initialContent || _saved;

  /// 用光标选区包裹语法（无选中则插入空语法并落在中间）。
  void _wrapSelection(String before, [String after = '']) {
    final value = _controller.value;
    final sel = value.selection;
    if (!sel.isValid) return;
    final selected = sel.textInside(value.text);
    final replaced = before + selected + after;
    _controller.value = value.copyWith(
      text: value.text.replaceRange(sel.start, sel.end, replaced),
      selection: TextSelection.collapsed(
        offset: sel.start + before.length + selected.length,
      ),
    );
    _focusNode.requestFocus();
  }

  /// 在光标所在行行首插入前缀（标题、列表、引用）。
  void _insertLinePrefix(String prefix) {
    final value = _controller.value;
    final sel = value.selection;
    final text = value.text;
    if (!sel.isValid) return;
    final caret = sel.start;
    final lineStart = caret == 0 ? 0 : text.lastIndexOf('\n', caret - 1) + 1;
    _controller.value = value.copyWith(
      text: text.replaceRange(lineStart, lineStart, prefix),
      selection: TextSelection.collapsed(offset: caret + prefix.length),
    );
    _focusNode.requestFocus();
  }

  Future<void> _save() async {
    if (_saving) return;
    final content = _controller.text;

    // 新建的空白笔记不保存，避免产生垃圾记录。
    if (widget.localPath == null && content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容为空，未保存')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      if (widget.localPath != null) {
        await FileManager.updateFile(widget.localPath!, content);
        await _updateHistoryRecord(content);
      } else {
        final fileName = defaultNoteName();
        final path = await FileManager.saveFile(fileName, content);
        await _appendHistoryRecord(fileName, content, path);
      }
      _saved = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  /// 编辑保存：更新 SP 历史里 localPath 对应记录的元数据。
  Future<void> _updateHistoryRecord(String content) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('file_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(historyJson);
    for (final e in decoded) {
      if (e is Map && e['localPath'] == widget.localPath) {
        e['contentHash'] = contentHashOf(content);
        e['wordCount'] = countWordsOf(content);
        e['fileSize'] = content.length;
        e['openedAt'] = DateTime.now().toIso8601String();
        break;
      }
    }
    await prefs.setString('file_history', jsonEncode(decoded));
  }

  /// 新建保存：在 SP 历史头部追加记录。
  Future<void> _appendHistoryRecord(
      String fileName, String content, String localPath) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('file_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(historyJson);
    decoded.insert(0, {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'fileName': fileName,
      'localPath': localPath,
      'openedAt': DateTime.now().toIso8601String(),
      'contentHash': contentHashOf(content),
      'wordCount': countWordsOf(content),
      'fileSize': content.length,
    });
    await prefs.setString('file_history', jsonEncode(decoded));
  }

  Future<void> _confirmExit() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('未保存的修改'),
        content: const Text('修改尚未保存，确定要退出吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('放弃修改',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.localPath == null ? '新建笔记' : '编辑',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: '保存',
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // 快捷插入栏：手机上输入 Markdown 符号费劲，提供常用语法一键插入
            Material(
              color: colorScheme.surfaceContainerLow,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    _shortcutButton('B', '粗体', () => _wrapSelection('**', '**')),
                    _shortcutButton('H', '标题', () => _insertLinePrefix('## ')),
                    _shortcutButton('</>', '代码', () => _wrapSelection('`', '`')),
                    _shortcutButton('•', '列表', () => _insertLinePrefix('- ')),
                    _shortcutButton('❝', '引用', () => _insertLinePrefix('> ')),
                    _shortcutButton('🔗', '链接', () => _wrapSelection('[', '](https://)')),
                    _shortcutButton('☰', '表格', () => _wrapSelection(
                        '\n| 列1 | 列2 |\n| --- | --- |\n| 内容 | 内容 |\n')),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => setState(() {}), // 刷新底部字数
                style: const TextStyle(
                  fontFamily: 'SF Mono',
                  fontSize: 14,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  hintText: '输入 Markdown 内容…\n\n上方工具栏可快捷插入语法',
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            // 底部状态栏：字数
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: colorScheme.surfaceContainerLow,
              child: Text(
                '${countWordsOf(_controller.text)} 字',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shortcutButton(String label, String tooltip, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}

class FileDetailScreen extends StatelessWidget {
  final String fileName;
  final String localPath;
  final String content;
  final VoidCallback? onDelete;

  const FileDetailScreen({
    super.key,
    required this.fileName,
    required this.localPath,
    required this.content,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // 详情页低频，同步读一次即可，但要容错：文件可能已被外部清理。
    final fileSize = FileManager.getFileSizeSync(localPath);
    final wordCount = content.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件详情'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.description,
                    size: 32,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('文件路径'),
            subtitle: Text(
              localPath,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: localPath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('路径已复制')),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('文件大小'),
            subtitle: Text(_formatFileSize(fileSize)),
          ),

          const SizedBox(height: 8),

          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字数统计'),
            subtitle: Text('$wordCount 字'),
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text(
              '删除文件',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text('确定要删除「$fileName」吗？'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () async {
                        await FileManager.deleteFile(localPath);
                        if (context.mounted) {
                          Navigator.pop(context);
                          Navigator.pop(context);
                          onDelete?.call();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('文件已删除')),
                          );
                        }
                      },
                      child: const Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 内置示例文档：首次进入空状态时点击「打开示例文档」展示。
/// 既演示麻雀MD 的 Markdown 渲染能力，又充当「怎么用」的引导。
const String _kDemoMarkdown = r'''# 欢迎使用麻雀MD 🕊️

麻雀MD 是一个轻量的文本阅读器。当你在**微信、文件管理器**或其他应用里收到 Markdown、日志、代码等文本文件时，选择用麻雀MD 打开，就能获得清爽舒适的阅读体验。

## 它能做什么

- 📖 渲染 Markdown：标题、列表、**粗体**、*斜体*、`行内代码`
- 📊 自动渲染表格和 Mermaid 流程图
- 🎨 代码高亮、亮暗主题
- 📂 支持任意文本文件：`.md` / `.txt` / `.log` / `.json` / `.csv` ...

## 怎么用

1. 在微信或文件管理器里**长按或点击**一个文本文件
2. 选择「**打开方式**」或「**分享**」
3. 选择 **麻雀MD**

> 💡 提示：打开过的文件会自动保存在首页，下次可以直接点开继续阅读。

---

下面是一些排版样例，看看麻雀MD 的渲染效果。

## 表格

| 类型 | 后缀 | 说明 |
| :--- | :--- | :--- |
| Markdown | .md .markdown | 完整渲染 |
| 纯文本 | .txt .log | 保留格式 |
| 代码 / 数据 | .json .csv .yaml | 代码高亮 |

## 代码块

```dart
void main() {
  // 麻雀MD，麻雀虽小，五脏俱全
  print('Hello, 麻雀MD!');
}
```

## 列表与引用

- 这是一条列表项
- 支持嵌套
  - 子列表项
- 还可以继续

> 这是一段引用，用来强调某段重要内容。
>
> 引用里也可以有**粗体**和 `代码`。

## 流程图

```mermaid
graph LR
  A[收到文本文件] --> B{选择打开方式}
  B -->|麻雀MD| C[舒适阅读]
  B -->|其他应用| D[体验不佳]
```

---

享受阅读，就这么简单。🕊️
''';
