import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'about_screen.dart';

void main() {
  runApp(const MDReaderApp());
}

class MDReaderApp extends StatelessWidget {
  const MDReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '麻袋咚 Dong MD',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.orange,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _channel = MethodChannel('com.inbox.md_reader/file');
  
  String? _filePath;
  String? _markdownContent;
  bool _isLoading = true;
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    
    // 监听来自 Android 原生的文件路径
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'loadContent') {
        final path = call.arguments['path'] as String;
        final content = call.arguments['content'] as String;
        
        setState(() {
          _filePath = path;
          _markdownContent = content;
          _isLoading = false;
        });
        
        // 加载到 WebView
        _loadMarkdownToWebView(content);
      }
    });
    
    // 初始化 WebView
    _initWebView();
  }
  
  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
        ),
      );
    
    // 加载初始 HTML
    _loadEmptyState();
  }
  
  void _loadEmptyState() {
    final html = _buildHtmlTemplate('# 麻袋咚 Dong MD\n\n打开文件管理器中的 Markdown 文件\n\n支持: .md, .markdown, .txt');
    _controller?.loadHtmlString(html);
  }
  
  void _loadMarkdownToWebView(String markdown) {
    final html = _buildHtmlTemplate(markdown);
    _controller?.loadHtmlString(html);
  }
  
  String _buildHtmlTemplate(String markdown) {
    // 转义 markdown 内容
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
    
    // 渲染 Markdown
    const html = marked.parse(markdown);
    document.getElementById('content').innerHTML = html;
    
    // 查找所有 mermaid 代码块并渲染
    document.querySelectorAll('pre code.language-mermaid').forEach(block => {
      const code = block.textContent;
      const pre = block.parentElement;
      
      // 创建 mermaid 容器
      const mermaidDiv = document.createElement('div');
      mermaidDiv.className = 'mermaid';
      mermaidDiv.textContent = code;
      
      // 替换 pre 标签
      pre.replaceWith(mermaidDiv);
    });
    
    // 渲染所有 mermaid 图表
    mermaid.init(undefined, '.mermaid');
    
    // 处理链接点击
    document.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        const href = link.getAttribute('href');
        if (href && (href.startsWith('http://') || href.startsWith('https://'))) {
          window.open(href, '_blank');
        }
      });
    });
  </script>
</body>
</html>
''';
  }

  // 分享功能
  void _shareMarkdown() {
    if (_markdownContent != null && _markdownContent!.isNotEmpty) {
      final fileName = _filePath?.split('/').last ?? 'Markdown';
      Share.share(
        _markdownContent!,
        subject: fileName,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可分享的内容'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // 打开关于页面
  void _openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AboutScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filePath?.split('/').last ?? '麻袋咚 Dong MD',
        ),
        actions: [
          // 分享按钮
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _markdownContent != null ? _shareMarkdown : null,
            tooltip: '分享',
          ),
          // 关于菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'about') {
                _openAbout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 12),
                    Text('关于'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_controller != null)
            WebViewWidget(controller: _controller!),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
