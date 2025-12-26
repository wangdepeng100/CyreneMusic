import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import '../../services/audio_source_service.dart';
import '../../services/lx_music_source_parser.dart';
import '../../services/url_service.dart';
import '../../utils/theme_manager.dart';

/// 音源设置二级页面内容
///
/// 与 ThirdPartyAccountsContent 结构类似，作为设置页面的子页面
class AudioSourceSettingsContent extends StatefulWidget {
  final VoidCallback? onBack;
  final bool embed;

  const AudioSourceSettingsContent({
    super.key,
    this.onBack,
    this.embed = false,
  });

  @override
  State<AudioSourceSettingsContent> createState() =>
      _AudioSourceSettingsContentState();

  /// 构建 Fluent UI 面包屑导航（Windows 11 24H2 风格）
  Widget buildFluentBreadcrumb(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final typography = theme.typography;

    return Row(
      children: [
        // 父级：设置（颜色较浅，可点击）
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onBack,
            child: Text(
              '设置',
              style: typography.title?.copyWith(
                color: theme.resources.textFillColorSecondary,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            fluent.FluentIcons.chevron_right,
            size: 14,
            color: theme.resources.textFillColorSecondary,
          ),
        ),
        // 当前页面：音源设置（正常颜色）
        Text(
          '音源设置',
          style: typography.title,
        ),
      ],
    );
  }
}

class _AudioSourceSettingsContentState
    extends State<AudioSourceSettingsContent> {
  // OmniParse 控制器
  final TextEditingController _urlController = TextEditingController();

  // 洛雪音源控制器
  final TextEditingController _lxScriptUrlController = TextEditingController();
  final TextEditingController _lxApiKeyController = TextEditingController();

  final AudioSourceService _audioSourceService = AudioSourceService();
  final LxMusicSourceParser _lxParser = LxMusicSourceParser();

  /// 是否需要用户手动输入 API Key（脚本中未包含 API Key）
  bool _needsApiKeyInput = false;

  bool _isTesting = false;
  bool _isImporting = false;
  String? _testResult;
  bool _testSuccess = false;
  String? _importResult;
  bool _importSuccess = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = _audioSourceService.sourceUrl;
    // 如果是洛雪音源，显示脚本来源和 API Key
    if (_audioSourceService.sourceType == AudioSourceType.lxmusic) {
      _lxScriptUrlController.text = _audioSourceService.lxScriptSource;
      _lxApiKeyController.text = _audioSourceService.lxApiKey;
      // 如果已配置但没有 API Key，显示输入框
      _needsApiKeyInput = _audioSourceService.isConfigured && _audioSourceService.lxApiKey.isEmpty;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _lxScriptUrlController.dispose();
    _lxApiKeyController.dispose();
    super.dispose();
  }

  /// 测试音源连接
  Future<void> _testConnection() async {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      setState(() {
        _testResult = '请输入音源地址';
        _testSuccess = false;
      });
      return;
    }

    if (!AudioSourceService.isValidUrl(url)) {
      setState(() {
        _testResult = 'URL 格式不正确，请输入 http:// 或 https:// 开头的地址';
        _testSuccess = false;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // 尝试访问音源根路径
      final response = await http
          .get(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        setState(() {
          _testResult = '连接成功！';
          _testSuccess = true;
        });
      } else {
        setState(() {
          _testResult = '连接失败：HTTP ${response.statusCode}';
          _testSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '连接失败：$e';
        _testSuccess = false;
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  /// 保存 OmniParse 音源配置
  void _saveOmniParseConfiguration() {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      _showMessage('请输入音源地址');
      return;
    }

    if (!AudioSourceService.isValidUrl(url)) {
      _showMessage('URL 格式不正确');
      return;
    }

    _audioSourceService.configure(
      AudioSourceType.omniparse,
      url,
    );

    _showMessage('OmniParse 音源配置已保存');
    // 如果有返回回调，则调用
    widget.onBack?.call();
  }

  /// 保存 TuneHub 音源配置
  void _saveTuneHubConfiguration() {
    final url = _urlController.text.trim();

    if (url.isEmpty) {
      _showMessage('请输入音源地址');
      return;
    }

    if (!AudioSourceService.isValidUrl(url)) {
      _showMessage('URL 格式不正确');
      return;
    }

    _audioSourceService.configure(
      AudioSourceType.tunehub,
      url,
    );

    _showMessage('TuneHub 音源配置已保存');
    // 如果有返回回调，则调用
    widget.onBack?.call();
  }

  /// 从 URL 导入洛雪音源脚本
  Future<void> _importLxScriptFromUrl() async {
    final scriptUrl = _lxScriptUrlController.text.trim();

    if (scriptUrl.isEmpty) {
      setState(() {
        _importResult = '请输入脚本链接';
        _importSuccess = false;
      });
      return;
    }

    if (!AudioSourceService.isValidUrl(scriptUrl)) {
      setState(() {
        _importResult = 'URL 格式不正确，请输入 http:// 或 https:// 开头的地址';
        _importSuccess = false;
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _importResult = null;
    });

    try {
      // 解析脚本内容
      final config = await _lxParser.parseFromUrl(scriptUrl);

      if (config == null || !config.isValid) {
        setState(() {
          _importResult = '解析失败：无法从脚本中提取 API 地址';
          _importSuccess = false;
        });
        return;
      }

      // 保存配置
      _audioSourceService.configureLxMusicSource(
        name: config.name,
        version: config.version,
        apiUrl: config.apiUrl,
        apiKey: config.apiKey,
        scriptSource: scriptUrl,
        urlPathTemplate: config.urlPathTemplate,
      );

      // 检查是否需要用户手动输入 API Key
      final needsApiKey = config.apiKey.isEmpty;

      setState(() {
        _importResult = '导入成功：${config.name} v${config.version}';
        _importSuccess = true;
        _needsApiKeyInput = needsApiKey;
        _lxApiKeyController.text = config.apiKey;
      });

      if (needsApiKey) {
        _showMessage('洛雪音源导入成功，请输入 API Key');
      } else {
        _showMessage('洛雪音源脚本导入成功');
      }
    } catch (e) {
      setState(() {
        _importResult = '导入失败：$e';
        _importSuccess = false;
      });
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  /// 从本地文件导入洛雪音源脚本
  Future<void> _importLxScriptFromFile() async {
    setState(() {
      _isImporting = true;
      _importResult = null;
    });

    try {
      // 从文件解析脚本内容
      final config = await _lxParser.parseFromFile();

      if (config == null) {
        setState(() {
          _importResult = '导入已取消或文件无效';
          _importSuccess = false;
        });
        return;
      }

      if (!config.isValid) {
        setState(() {
          _importResult = '解析失败：无法从脚本中提取 API 地址';
          _importSuccess = false;
        });
        return;
      }

      // 保存配置
      _audioSourceService.configureLxMusicSource(
        name: config.name,
        version: config.version,
        apiUrl: config.apiUrl,
        apiKey: config.apiKey,
        scriptSource: config.source,
        urlPathTemplate: config.urlPathTemplate,
      );

      // 检查是否需要用户手动输入 API Key
      final needsApiKey = config.apiKey.isEmpty;

      setState(() {
        _importResult = '导入成功：${config.name} v${config.version}';
        _importSuccess = true;
        _lxScriptUrlController.text = config.source;
        _needsApiKeyInput = needsApiKey;
        _lxApiKeyController.text = config.apiKey;
      });

      if (needsApiKey) {
        _showMessage('洛雪音源导入成功，请输入 API Key');
      } else {
        _showMessage('洛雪音源脚本导入成功');
      }
    } catch (e) {
      setState(() {
        _importResult = '导入失败：$e';
        _importSuccess = false;
      });
    } finally {
      setState(() {
        _isImporting = false;
      });
    }
  }

  /// 清除音源配置
  void _clearConfiguration() {
    _audioSourceService.clear();
    _urlController.clear();
    _lxScriptUrlController.clear();
    _lxApiKeyController.clear();
    setState(() {
      _testResult = null;
      _importResult = null;
      _needsApiKeyInput = false;
    });
    _showMessage('音源配置已清除');
  }

  /// 保存手动输入的 API Key
  void _saveLxApiKey() {
    final apiKey = _lxApiKeyController.text.trim();
    _audioSourceService.setLxApiKey(apiKey);
    setState(() {
      _needsApiKeyInput = false;
    });
    _showMessage('API Key 已保存');
  }

  void _showMessage(String message) {
    final themeManager = ThemeManager();

    if (themeManager.isFluentFramework && Platform.isWindows) {
      fluent.displayInfoBar(
        context,
        builder: (context, close) {
          return fluent.InfoBar(
            title: Text(message),
            severity: fluent.InfoBarSeverity.info,
          );
        },
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();

    if (themeManager.isFluentFramework && Platform.isWindows) {
      return _buildFluentContent(context);
    } else if (themeManager.isCupertinoFramework &&
        (Platform.isIOS || Platform.isAndroid)) {
      return _buildCupertinoContent(context);
    } else {
      return _buildMaterialContent(context);
    }
  }

  /// 当前是否选择了洛雪音源类型
  bool get _isLxMusicSelected =>
      _audioSourceService.sourceType == AudioSourceType.lxmusic;

  /// 当前是否选择了 TuneHub 音源类型
  bool get _isTuneHubSelected =>
      _audioSourceService.sourceType == AudioSourceType.tunehub;

  /// 获取音源类型名称
  String _getSourceTypeName(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse:
        return 'OmniParse';
      case AudioSourceType.lxmusic:
        return '洛雪音乐';
      case AudioSourceType.tunehub:
        return 'TuneHub';
    }
  }

  /// 获取音源类型描述
  String _getSourceTypeDescription(AudioSourceType type) {
    switch (type) {
      case AudioSourceType.omniparse:
        return '手动输入 API 地址';
      case AudioSourceType.lxmusic:
        return '导入 JS 脚本文件或链接';
      case AudioSourceType.tunehub:
        return '公开 API（无需认证）';
    }
  }

  /// Fluent UI 风格 (Windows)
  Widget _buildFluentContent(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);

    return fluent.ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 说明卡片
        fluent.Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(fluent.FluentIcons.info, color: theme.accentColor),
                    const SizedBox(width: 8),
                    Text(
                      '关于音源',
                      style: theme.typography.subtitle,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '音源是用于获取歌曲播放链接的服务。由于版权保护原因，应用不内置音源，'
                  '您需要自行配置音源才能播放在线音乐。',
                  style: theme.typography.body,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 当前配置状态
        if (_audioSourceService.isConfigured)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: fluent.InfoBar(
              title: Text(_audioSourceService.sourceType == AudioSourceType.lxmusic
                  ? '已配置：${_audioSourceService.lxSourceName} v${_audioSourceService.lxSourceVersion}'
                  : '已配置：${_audioSourceService.sourceUrl}'),
              severity: fluent.InfoBarSeverity.success,
            ),
          ),

        // 音源类型选择
        Text('音源类型', style: theme.typography.subtitle),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: fluent.ComboBox<AudioSourceType>(
              value: _audioSourceService.sourceType,
              items: AudioSourceType.values.map((type) {
                return fluent.ComboBoxItem<AudioSourceType>(
                  value: type,
                  child: Text(_getSourceTypeName(type)),
                );
              }).toList(),
              onChanged: (type) {
                if (type != null) {
                  setState(() {
                    _audioSourceService.setSourceType(type);
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 根据音源类型显示不同的配置界面
        if (_isLxMusicSelected) ...[
          // 洛雪音源：脚本导入
          Text('导入音源脚本', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Text(
            '输入洛雪音源脚本的 URL 链接，或从本地导入 .js 文件',
            style: theme.typography.caption,
          ),
          const SizedBox(height: 12),
          fluent.TextBox(
            controller: _lxScriptUrlController,
            placeholder: '例如：https://example.com/lxmusic-source.js',
            suffix: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : null,
          ),
          const SizedBox(height: 16),

          // 导入结果
          if (_importResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: fluent.InfoBar(
                title: Text(_importResult!),
                severity: _importSuccess
                    ? fluent.InfoBarSeverity.success
                    : fluent.InfoBarSeverity.error,
              ),
            ),

          // 导入按钮
          Row(
            children: [
              fluent.FilledButton(
                onPressed: _isImporting ? null : _importLxScriptFromUrl,
                child: const Text('从链接导入'),
              ),
              const SizedBox(width: 12),
              fluent.Button(
                onPressed: _isImporting ? null : _importLxScriptFromFile,
                child: const Text('从文件导入'),
              ),
              const Spacer(),
              fluent.Button(
                onPressed: _clearConfiguration,
                child: Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),

          // API Key 输入区域（仅在需要时显示）
          if (_needsApiKeyInput || (_audioSourceService.isConfigured && _audioSourceService.sourceType == AudioSourceType.lxmusic)) ...[
            const SizedBox(height: 24),
            Text('API Key', style: theme.typography.subtitle),
            const SizedBox(height: 8),
            Text(
              _needsApiKeyInput 
                  ? '此音源需要 API Key 才能使用，请输入音源提供者给您的密钥'
                  : '可选，用于验证音源请求',
              style: theme.typography.caption,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: fluent.TextBox(
                    controller: _lxApiKeyController,
                    placeholder: '输入 API Key（部分音源需要）',
                    obscureText: true,
                  ),
                ),
                const SizedBox(width: 12),
                fluent.FilledButton(
                  onPressed: _saveLxApiKey,
                  child: const Text('保存'),
                ),
              ],
            ),
            if (_needsApiKeyInput)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: fluent.InfoBar(
                  title: const Text('请输入 API Key'),
                  content: const Text('此音源脚本未包含 API Key，您需要手动输入'),
                  severity: fluent.InfoBarSeverity.warning,
                ),
              ),
          ],
        ] else if (_isTuneHubSelected) ...[
          // TuneHub：手动输入地址（公开 API，无需认证）
          Text('音源地址', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          Text(
            'TuneHub',
            style: theme.typography.caption,
          ),
          const SizedBox(height: 12),
          fluent.TextBox(
            controller: _urlController,
            placeholder: '请输入音源地址',
            suffix: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : null,
          ),

          const SizedBox(height: 16),

          // 测试结果
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: fluent.InfoBar(
                title: Text(_testResult!),
                severity: _testSuccess
                    ? fluent.InfoBarSeverity.success
                    : fluent.InfoBarSeverity.error,
              ),
            ),

          // 操作按钮
          Row(
            children: [
              fluent.Button(
                onPressed: _isTesting ? null : _testConnection,
                child: const Text('测试连接'),
              ),
              const SizedBox(width: 12),
              fluent.FilledButton(
                onPressed: _saveTuneHubConfiguration,
                child: const Text('保存配置'),
              ),
              const Spacer(),
              fluent.Button(
                onPressed: _clearConfiguration,
                child: Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        ] else ...[
          // OmniParse：手动输入地址
          Text('音源地址', style: theme.typography.subtitle),
          const SizedBox(height: 8),
          fluent.TextBox(
            controller: _urlController,
            placeholder: '例如：http://localhost:4055',
            suffix: _isTesting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: fluent.ProgressRing(strokeWidth: 2),
                  )
                : null,
          ),

          const SizedBox(height: 16),

          // 测试结果
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: fluent.InfoBar(
                title: Text(_testResult!),
                severity: _testSuccess
                    ? fluent.InfoBarSeverity.success
                    : fluent.InfoBarSeverity.error,
              ),
            ),

          // 操作按钮
          Row(
            children: [
              fluent.Button(
                onPressed: _isTesting ? null : _testConnection,
                child: const Text('测试连接'),
              ),
              const SizedBox(width: 12),
              fluent.FilledButton(
                onPressed: _saveOmniParseConfiguration,
                child: const Text('保存配置'),
              ),
              const Spacer(),
              fluent.Button(
                onPressed: _clearConfiguration,
                child: Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Cupertino 风格 (iOS/Android)
  Widget _buildCupertinoContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? CupertinoColors.black : CupertinoColors.systemGroupedBackground;

    return Container(
      color: backgroundColor,
      child: CupertinoScrollbar(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 说明卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.info_circle,
                        color: CupertinoTheme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '关于音源',
                        style: CupertinoTheme.of(context)
                            .textTheme
                            .navTitleTextStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '音源是用于获取歌曲播放链接的服务。由于版权保护原因，应用不内置音源，'
                    '您需要自行配置音源才能播放在线音乐。',
                    style: CupertinoTheme.of(context).textTheme.textStyle,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 音源类型
            CupertinoListSection.insetGrouped(
              header: const Text('音源类型'),
              children: AudioSourceType.values.map((type) {
                return CupertinoListTile(
                  title: Text(_getSourceTypeName(type)),
                  subtitle: Text(_getSourceTypeDescription(type)),
                  trailing: _audioSourceService.sourceType == type
                      ? const Icon(CupertinoIcons.checkmark,
                          color: CupertinoColors.activeBlue)
                      : null,
                  onTap: () {
                    setState(() {
                      _audioSourceService.setSourceType(type);
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // 根据音源类型显示不同内容
            if (_isLxMusicSelected) ...[
              // 洛雪音源：脚本导入
              CupertinoListSection.insetGrouped(
                header: const Text('导入音源脚本'),
                footer:
                    const Text('输入洛雪音源脚本的 URL 链接，或点击下方按钮从本地导入'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _lxScriptUrlController,
                    placeholder: '输入脚本 URL 链接',
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),

              // 导入结果
              if (_importResult != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _importSuccess
                          ? CupertinoColors.systemGreen.withOpacity(0.1)
                          : CupertinoColors.systemRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _importSuccess
                              ? CupertinoIcons.checkmark_circle
                              : CupertinoIcons.xmark_circle,
                          color: _importSuccess
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_importResult!)),
                      ],
                    ),
                  ),
                ),

              // 导入按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed:
                            _isImporting ? null : _importLxScriptFromUrl,
                        child: _isImporting
                            ? const CupertinoActivityIndicator()
                            : const Text('从链接导入'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed:
                            _isImporting ? null : _importLxScriptFromFile,
                        child: const Text('从文件导入'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _clearConfiguration,
                        child: const Text(
                          '清除配置',
                          style:
                              TextStyle(color: CupertinoColors.destructiveRed),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // API Key 输入区域（仅在需要时显示）
              if (_needsApiKeyInput || (_audioSourceService.isConfigured && _audioSourceService.sourceType == AudioSourceType.lxmusic)) ...[
                const SizedBox(height: 16),
                CupertinoListSection.insetGrouped(
                  header: Text(_needsApiKeyInput ? 'API Key（必填）' : 'API Key（可选）'),
                  footer: Text(
                    _needsApiKeyInput 
                        ? '此音源需要 API Key 才能使用，请输入音源提供者给您的密钥'
                        : '部分音源需要 API Key 进行验证',
                  ),
                  children: [
                    CupertinoTextFormFieldRow(
                      controller: _lxApiKeyController,
                      placeholder: '输入 API Key',
                      obscureText: true,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: _saveLxApiKey,
                      child: const Text('保存 API Key'),
                    ),
                  ),
                ),
                if (_needsApiKeyInput)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemOrange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            color: CupertinoColors.systemOrange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '此音源脚本未包含 API Key，您需要手动输入',
                              style: TextStyle(color: CupertinoColors.systemOrange),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ] else if (_isTuneHubSelected) ...[
              // TuneHub：手动输入地址
              CupertinoListSection.insetGrouped(
                header: const Text('音源地址'),
                footer:
                    const Text('TuneHub 是公开 API，无需认证'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _urlController,
                    placeholder: '请输入音源地址',
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),

              // 测试结果
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _testSuccess
                          ? CupertinoColors.systemGreen.withOpacity(0.1)
                          : CupertinoColors.systemRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testSuccess
                              ? CupertinoIcons.checkmark_circle
                              : CupertinoIcons.xmark_circle,
                          color: _testSuccess
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_testResult!)),
                      ],
                    ),
                  ),
                ),

              // 操作按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? const CupertinoActivityIndicator()
                            : const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: _saveTuneHubConfiguration,
                        child: const Text('保存配置'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _clearConfiguration,
                        child: const Text(
                          '清除配置',
                          style:
                              TextStyle(color: CupertinoColors.destructiveRed),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // OmniParse：手动输入地址
              CupertinoListSection.insetGrouped(
                header: const Text('音源地址'),
                children: [
                  CupertinoTextFormFieldRow(
                    controller: _urlController,
                    placeholder: '例如：http://localhost:4055',
                    keyboardType: TextInputType.url,
                  ),
                ],
              ),

              // 测试结果
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _testSuccess
                          ? CupertinoColors.systemGreen.withOpacity(0.1)
                          : CupertinoColors.systemRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testSuccess
                              ? CupertinoIcons.checkmark_circle
                              : CupertinoIcons.xmark_circle,
                          color: _testSuccess
                              ? CupertinoColors.systemGreen
                              : CupertinoColors.systemRed,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_testResult!)),
                      ],
                    ),
                  ),
                ),

              // 操作按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? const CupertinoActivityIndicator()
                            : const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton.filled(
                        onPressed: _saveOmniParseConfiguration,
                        child: const Text('保存配置'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _clearConfiguration,
                        child: const Text(
                          '清除配置',
                          style:
                              TextStyle(color: CupertinoColors.destructiveRed),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Material Design 风格
  Widget _buildMaterialContent(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 说明卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '关于音源',
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '音源是用于获取歌曲播放链接的服务。由于版权保护原因，应用不内置音源，'
                  '您需要自行配置音源才能播放在线音乐。',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 音源类型选择
        Text('音源类型', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DropdownButtonFormField<AudioSourceType>(
              value: _audioSourceService.sourceType,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
              ),
              items: AudioSourceType.values.map((type) {
                return DropdownMenuItem<AudioSourceType>(
                  value: type,
                  child: Text(_getSourceTypeName(type)),
                );
              }).toList(),
              onChanged: (type) {
                if (type != null) {
                  setState(() {
                    _audioSourceService.setSourceType(type);
                  });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 24),

        // 根据音源类型显示不同配置
        if (_isLxMusicSelected) ...[
          // 洛雪音源：脚本导入
          Text('导入音源脚本', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '输入洛雪音源脚本的 URL 链接，或从本地导入 .js 文件',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lxScriptUrlController,
            decoration: InputDecoration(
              hintText: '例如：https://example.com/lxmusic-source.js',
              border: const OutlineInputBorder(),
              suffixIcon: _isImporting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 16),

          // 导入结果
          if (_importResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _importSuccess
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _importSuccess ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _importSuccess ? Icons.check_circle : Icons.error,
                      color: _importSuccess ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_importResult!)),
                  ],
                ),
              ),
            ),

          // 导入按钮
          Row(
            children: [
              ElevatedButton(
                onPressed: _isImporting ? null : _importLxScriptFromUrl,
                child: const Text('从链接导入'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _isImporting ? null : _importLxScriptFromFile,
                child: const Text('从文件导入'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearConfiguration,
                child: const Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),

          // API Key 输入区域（仅在需要时显示）
          if (_needsApiKeyInput || (_audioSourceService.isConfigured && _audioSourceService.sourceType == AudioSourceType.lxmusic)) ...[
            const SizedBox(height: 24),
            Text(
              _needsApiKeyInput ? 'API Key（必填）' : 'API Key（可选）',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              _needsApiKeyInput 
                  ? '此音源需要 API Key 才能使用，请输入音源提供者给您的密钥'
                  : '部分音源需要 API Key 进行验证',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _lxApiKeyController,
                    decoration: const InputDecoration(
                      hintText: '输入 API Key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveLxApiKey,
                  child: const Text('保存'),
                ),
              ],
            ),
            if (_needsApiKeyInput)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '此音源脚本未包含 API Key，您需要手动输入',
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ] else if (_isTuneHubSelected) ...[
          // TuneHub：手动输入地址
          Text('音源地址', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'TuneHub 是公开 API，无需认证',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: '请输入音源地址',
              border: const OutlineInputBorder(),
              suffixIcon: _isTesting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 16),

          // 测试结果
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess ? Icons.check_circle : Icons.error,
                      color: _testSuccess ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_testResult!)),
                  ],
                ),
              ),
            ),

          // 操作按钮
          Row(
            children: [
              OutlinedButton(
                onPressed: _isTesting ? null : _testConnection,
                child: const Text('测试连接'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveTuneHubConfiguration,
                child: const Text('保存配置'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearConfiguration,
                child: const Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ] else ...[
          // OmniParse：手动输入地址
          Text('音源地址', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: '例如：http://localhost:4055',
              border: const OutlineInputBorder(),
              suffixIcon: _isTesting
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            keyboardType: TextInputType.url,
          ),

          const SizedBox(height: 16),

          // 测试结果
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess ? Colors.green : Colors.red,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess ? Icons.check_circle : Icons.error,
                      color: _testSuccess ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_testResult!)),
                  ],
                ),
              ),
            ),

          // 操作按钮
          Row(
            children: [
              OutlinedButton(
                onPressed: _isTesting ? null : _testConnection,
                child: const Text('测试连接'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveOmniParseConfiguration,
                child: const Text('保存配置'),
              ),
              const Spacer(),
              TextButton(
                onPressed: _clearConfiguration,
                child: const Text(
                  '清除配置',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
