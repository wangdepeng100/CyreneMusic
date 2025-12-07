import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent_ui;
import 'package:url_launcher/url_launcher.dart';

import 'settings_page/donate_settings.dart';
import 'settings_page/sponsor_wall.dart';
import '../utils/theme_manager.dart';
import '../services/app_config_service.dart';
import '../widgets/fluent_settings_card.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  AppPublicConfig? _config;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await AppConfigService().fetchPublicConfig();
      if (mounted) {
        setState(() {
          _config = config;
          _loading = false;
        });
      }
    } catch (e) {
      print('[SupportPage] 加载配置失败: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openQQGroup() async {
    final url = _config?.qqGroup.url;
    if (url == null || url.isEmpty) return;

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('[SupportPage] 无法打开链接: $url');
      }
    } catch (e) {
      print('[SupportPage] 打开QQ群链接失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFluentUI = Platform.isWindows && ThemeManager().isFluentFramework;

    if (isFluentUI) {
      return fluent_ui.ScaffoldPage.scrollable(
        padding: const EdgeInsets.all(24.0),
        header: const fluent_ui.PageHeader(
          title: Text('支持'),
        ),
        children: [
          const DonateSettings(),
          const SizedBox(height: 16),
          // QQ群入口
          if (!_loading && _config?.qqGroup.enabled == true)
            _buildFluentQQGroupSection(),
          if (!_loading && _config?.qqGroup.enabled == true)
            const SizedBox(height: 16),
          const SponsorWall(),
          const SizedBox(height: 40),
        ],
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: colorScheme.surface,
            title: Text(
              '支持',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const DonateSettings(),
                const SizedBox(height: 24),
                // QQ群入口
                if (!_loading && _config?.qqGroup.enabled == true)
                  _buildMaterialQQGroupSection(context),
                if (!_loading && _config?.qqGroup.enabled == true)
                  const SizedBox(height: 24),
                const SponsorWall(),
                const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFluentQQGroupSection() {
    final groupName = _config?.qqGroup.name ?? 'QQ群';
    return FluentSettingsGroup(
      title: '加入社区',
      children: [
        FluentSettingsTile(
          icon: fluent_ui.FluentIcons.people,
          title: '加入QQ群',
          subtitle: groupName,
          trailing: const Icon(Icons.chevron_right),
          onTap: _openQQGroup,
        ),
      ],
    );
  }

  Widget _buildMaterialQQGroupSection(BuildContext context) {
    final groupName = _config?.qqGroup.name ?? 'QQ群';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0, left: 4.0),
          child: Text(
            '加入社区',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.people_outline),
            title: const Text('加入QQ群'),
            subtitle: Text(groupName),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openQQGroup,
          ),
        ),
      ],
    );
  }
}
