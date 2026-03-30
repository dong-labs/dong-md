import 'dart:io';
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
  final String content;
  final DateTime openedAt;

  FileRecord({
    required this.id,
    required this.fileName,
    required this.localPath,
    required this.content,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'localPath': localPath,
    'content': content,
    'openedAt': openedAt.toIso8601String(),
  };

  factory FileRecord.fromJson(Map<String, dynamic> json) => FileRecord(
    id: json['id'],
    fileName: json['fileName'],
    localPath: json['localPath'],
    content: json['content'],
    openedAt: DateTime.parse(json['openedAt']),
  );
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
  
  static Future<int> getFileSize(String path) async {
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
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

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.inbox.md_reader/file');
  
  List<FileRecord> _history = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = '';
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _setupMethodCallHandler();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString('file_history') ?? '[]';
    final List<dynamic> decoded = jsonDecode(historyJson);
    setState(() {
      _history = decoded.map((e) => FileRecord.fromJson(e)).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = jsonEncode(_history.map((e) => e.toJson()).toList());
    await prefs.setString('file_history', historyJson);
  }

  Future<void> _addFileToHistory(String fileName, String content) async {
    final localPath = await FileManager.saveFile(fileName, content);
    
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final record = FileRecord(
      id: id,
      fileName: fileName,
      localPath: localPath,
      content: content,
      openedAt: DateTime.now(),
    );
    setState(() {
      _history.insert(0, record);
    });
    await _saveHistory();
  }

  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'loadContent') {
        final path = call.arguments['path'] as String?;
        final content = call.arguments['content'] as String;
        final fileName = path?.split('/').last ?? '未命名.md';
        
        await _addFileToHistory(fileName, content);
        
        final localPath = await FileManager.saveFile(fileName, content);
        
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReaderScreen(
                fileName: fileName,
                content: content,
                localPath: localPath,
              ),
            ),
          );
        }
      }
    });
  }

  List<FileRecord> get _filteredHistory {
    if (_searchQuery.isEmpty) return _history;
    return _history.where((record) => 
      record.fileName.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
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
            Icon(Icons.search_off, size: 64, color: Colors.grey),
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
        return _buildHistoryItem(record);
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
                      '支持 .md / .markdown / .txt',
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

  Widget _buildHistoryItem(FileRecord record) {
    final fileSize = File(record.localPath).lengthSync();
    final wordCount = record.content.length;
    
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
            '${_formatDate(record.openedAt)} · ${_formatFileSize(fileSize)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '$wordCount 字',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) {
          if (value == 'open') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ReaderScreen(
                  fileName: record.fileName,
                  content: record.content,
                  localPath: record.localPath,
                ),
              ),
            );
          } else if (value == 'share_content') {
            Share.share(record.content, subject: record.fileName);
          } else if (value == 'share_file') {
            Share.shareXFiles(
              [XFile(record.localPath)],
              subject: record.fileName,
            );
          } else if (value == 'detail') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FileDetailScreen(
                  fileName: record.fileName,
                  localPath: record.localPath,
                  content: record.content,
                  onDelete: () {
                    setState(() {
                      _history.removeWhere((r) => r.id == record.id);
                    });
                    _saveHistory();
                  },
                ),
              ),
            );
          } else if (value == 'delete') {
            _showDeleteDialog(record);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'open',
            child: ListTile(
              leading: Icon(Icons.open_in_new),
              title: Text('打开'),
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
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ReaderScreen(
              fileName: record.fileName,
              content: record.content,
              localPath: record.localPath,
            ),
          ),
        );
      },
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
    } else {
      return '${date.month}-${date.day}';
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

  const ReaderScreen({
    super.key,
    required this.fileName,
    required this.content,
    required this.localPath,
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
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_buildHtmlTemplate(widget.content));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
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

  String _buildHtmlTemplate(String markdown) {
    final escapedMarkdown = markdown
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');
    
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      padding: 16px;
      background: #fff;
      color: #333;
      line-height: 1.6;
    }
    pre {
      background: #f5f5f5;
      padding: 12px;
      border-radius: 8px;
      overflow-x: auto;
    }
    code {
      font-family: "SF Mono", Monaco, monospace;
      font-size: 14px;
    }
    table {
      border-collapse: collapse;
      width: 100%;
      margin: 16px 0;
    }
    th, td {
      border: 1px solid #ddd;
      padding: 8px;
      text-align: left;
    }
    th {
      background: #f5f5f5;
      font-weight: bold;
    }
    .mermaid {
      background: #fafafa;
      padding: 16px;
      border-radius: 8px;
      margin: 16px 0;
      text-align: center;
    }
    a {
      color: #ff9800;
      text-decoration: none;
    }
    h1, h2, h3, h4, h5, h6 {
      margin-top: 24px;
      margin-bottom: 16px;
      font-weight: 600;
    }
    h1 { font-size: 2em; border-bottom: 1px solid #eee; padding-bottom: 8px; }
    h2 { font-size: 1.5em; }
    h3 { font-size: 1.25em; }
    blockquote {
      border-left: 4px solid #ddd;
      padding-left: 16px;
      color: #666;
      margin: 16px 0;
    }
    ul, ol {
      padding-left: 24px;
    }
    li {
      margin: 8px 0;
    }
  </style>
</head>
<body>
  <div id="content">Loading...</div>
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/mermaid/dist/mermaid.min.js"></script>
  <script>
    mermaid.initialize({ 
      startOnLoad: false,
      theme: 'default'
    });
    
    const markdown = `$escapedMarkdown`;
    
    const html = marked.parse(markdown);
    document.getElementById('content').innerHTML = html;
    
    document.querySelectorAll('pre code.language-mermaid').forEach(block => {
      const code = block.textContent;
      const pre = block.parentElement;
      const mermaidDiv = document.createElement('div');
      mermaidDiv.className = 'mermaid';
      mermaidDiv.textContent = code;
      pre.replaceWith(mermaidDiv);
    });
    
    mermaid.init(undefined, '.mermaid');
  </script>
</body>
</html>
''';
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
    final fileSize = File(localPath).lengthSync();
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

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF9800), Color(0xFFF57C00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.orange.withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.description,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 24),
              
              const Text(
                'Dong MD',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                '阅读 Markdown，就这么简单',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              
              const SizedBox(height: 8),
              
              Text(
                'v1.4.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              
              const SizedBox(height: 32),
              
              _buildInfoCard(
                icon: Icons.person,
                title: '开发者',
                value: '咕咚同学',
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '咕咚同学'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制')),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              _buildInfoCard(
                icon: Icons.forum,
                title: '公众号',
                value: '咕咚同学',
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '咕咚同学'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制')),
                  );
                },
              ),
              
              const SizedBox(height: 12),
              
              _buildInfoCard(
                icon: Icons.web,
                title: '博客',
                value: 'gudong.site',
                onTap: () {
                  launchUrl(Uri.parse('https://gudong.site'));
                },
              ),
              
              const SizedBox(height: 12),
              
              _buildInfoCard(
                icon: Icons.code,
                title: 'GitHub',
                value: 'github.com/dong-labs/dong-md',
                onTap: () {
                  launchUrl(Uri.parse('https://github.com/dong-labs/dong-md'));
                },
              ),
              
              const SizedBox(height: 32),
              
              Text(
                '支持 Markdown 和 Mermaid 流程图',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(icon, color: Colors.orange),
        title: Text(title),
        subtitle: Text(value),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
