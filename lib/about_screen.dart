import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  String _buildNumber = '';

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    });
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label 已复制'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            
            // App 图标
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.primaryContainer,
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 50,
                color: Colors.white,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // App 名称
            Text(
              '麻袋咚 Dong MD',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
            ),
            
            const SizedBox(height: 8),
            
            // 版本号
            if (_version.isNotEmpty)
              Text(
                'v$_version${_buildNumber.isNotEmpty ? ' ($_buildNumber)' : ''}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            
            const SizedBox(height: 8),
            
            // 描述
            Text(
              '简洁的 Markdown 阅读器',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            
            const SizedBox(height: 48),
            
            // 开发信息
            _buildInfoCard(
              icon: Icons.person_outline,
              title: '开发者',
              subtitle: '咕咚同学',
              onTap: () => _copyToClipboard('咕咚同学', '开发者'),
            ),
            
            const SizedBox(height: 16),
            
            _buildInfoCard(
              icon: Icons.wechat_outlined,
              title: '公众号',
              subtitle: '咕咚同学',
              onTap: () => _copyToClipboard('咕咚同学', '公众号'),
            ),
            
            const SizedBox(height: 16),
            
            _buildInfoCard(
              icon: Icons.language_outlined,
              title: '博客',
              subtitle: 'gudong.site',
              trailing: Icons.open_in_new,
              onTap: () => _launchUrl('https://gudong.site'),
            ),
            
            const SizedBox(height: 16),
            
            _buildInfoCard(
              icon: Icons.code_outlined,
              title: 'GitHub',
              subtitle: 'github.com/dong-labs',
              trailing: Icons.open_in_new,
              onTap: () => _launchUrl('https://github.com/dong-labs'),
            ),
            
            const SizedBox(height: 48),
            
            // 版权信息
            Text(
              '© 2024 咕咚同学',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            
            const SizedBox(height: 8),
            
            Text(
              'Made with ❤️ in Flutter',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    IconData? trailing,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Icon(
                  trailing,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
