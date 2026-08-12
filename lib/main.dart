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
  runApp(const DongMDApp());
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

class DongMDApp extends StatelessWidget {
  const DongMDApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dong MD',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
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
  static const _channel = MethodChannel('com.inbox.md_reader/file');

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

  /// 计算内容指纹。不引入额外依赖，用字符串 hashCode（去重场景足够，
  /// 碰撞概率极低且后果仅为多保留一条记录，不影响数据正确性）。
  String _contentHash(String content) => 'h${content.hashCode}';

  /// 字数统计：去除 Markdown 常见语法符号后的可见字符数，
  /// 比纯 content.length 更接近真实阅读量。
  int _countWords(String content) {
    final cleaned = content
        .replaceAll(RegExp(r'```[\s\S]*?```'), '') // 代码块
        .replaceAll(RegExp(r'`[^`]*`'), '') // 行内代码
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '') // 图片
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1') // 链接保留文字
        .replaceAll(RegExp(r'[#>*_~\-]'), '') // 语法符号
        .replaceAll(RegExp(r'\s+'), '');
    return cleaned.length;
  }

  Future<FileRecord> _addFileToHistory(String fileName, String content) async {
    final localPath = await FileManager.saveFile(fileName, content);
    final hash = _contentHash(content);
    final now = DateTime.now();
    final wordCount = _countWords(content);
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
          : const Text('Dong MD'),
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
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.description,
                size: 40,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 24),

            // 标题
            const Text(
              'Dong MD',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Slogan
            Text(
              '阅读 Markdown，就这么简单',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),

            const SizedBox(height: 48),

            // 功能说明卡片
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildFeatureItem(
                      Icons.share,
                      '从其他应用分享',
                      '微信 / Telegram / 文件管理器',
                    ),
                    const Divider(),
                    _buildFeatureItem(
                      Icons.folder_open,
                      '从文件管理器打开',
                      '支持任意文本文件（.md / .txt / .log / .json ...）',
                    ),
                    const Divider(),
                    _buildFeatureItem(
                      Icons.auto_awesome,
                      '支持 Mermaid 流程图',
                      '自动渲染表格和流程图',
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

  Widget _buildFeatureItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: Colors.orange),
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
            // 页面就绪信号：reader.html load 后会设置 hash = 'reader-ready'，
            // 此时 DOM 与脚本已加载，通过 JS 桥接注入 markdown 内容。
            if (request.url.contains('#reader-ready')) {
              _injectContent();
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadFlutterAsset('assets/web/reader.html');
  }

  /// 通过 JS 调用 HTML 内的 setContent 注入正文和文件类型。
  /// 用 jsonEncode 转义，任何字符（含 `</script>`、反引号、$）都作为合法 JS
  /// 字符串字面量传递，彻底规避 HTML 解析层面的注入风险。
  void _injectContent() {
    final encodedContent = jsonEncode(widget.content);
    final encodedType = jsonEncode(widget.fileType.name);
    _controller.runJavaScript('window.setContent($encodedContent, $encodedType);');
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
                Share.share(widget.content, subject: widget.fileName);
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
              if (value == 'detail') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FileDetailScreen(
                      fileName: widget.fileName,
                      localPath: widget.localPath,
                      content: widget.content,
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
