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
  final String localPath;  // 本地保存路径
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
    
    // 检查重名
    if (File(targetPath).existsSync()) {
      final existingContent = File(targetPath).readAsStringSync();
      if (existingContent == content) {
        return targetPath; // 内容相同，不覆盖
      }
      
      // 内容不同，添加后缀
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
          return targetPath; // 找到相同内容的文件
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
    // 保存到本地文件
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
        
        // 添加到历史（保存内容到本地）
        await _addFileToHistory(fileName, content);
        
        // 保存文件获取本地路径
        final localPath = await FileManager.saveFile(fileName, content);
        
        // 跳转到阅读页面
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dong MD'),
        actions: [
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Dong MD',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '阅读 Markdown，就这么简单',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            const Text(
              '从文件管理器打开 Markdown 文件',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '支持：.md, .markdown, .txt',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final record = _history[index];
        
        return ListTile(
          leading: const Icon(Icons.description, color: Colors.orange),
          title: Text(record.fileName),
          subtitle: Text(
            _formatDate(record.openedAt),
            style: const TextStyle(fontSize: 12),
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
      },
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
            // 外部链接用系统浏览器打开
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

  const FileDetailScreen({
    super.key,
    required this.fileName,
    required this.localPath,
    required this.content,
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
          // 文件图标和名称
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
          
          // 文件路径
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
          
          // 文件大小
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('文件大小'),
            subtitle: Text(_formatFileSize(fileSize)),
          ),
          
          const SizedBox(height: 8),
          
          // 字数统计
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('字数统计'),
            subtitle: Text('$wordCount 字'),
          ),
          
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          
          // 删除按钮
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
                          Navigator.pop(context); // 关闭对话框
                          Navigator.pop(context); // 返回上一页
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
              
              // App 图标
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
              
              // App 名称
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
              
              const SizedBox(height: 8),
              
              // 版本
              Text(
                'v1.3.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // 信息卡片
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
              
              // 底部说明
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
