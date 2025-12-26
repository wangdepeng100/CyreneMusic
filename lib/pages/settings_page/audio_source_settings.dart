import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:http/http.dart' as http;
import '../../services/audio_source_service.dart';
import '../../services/lx_music_source_parser.dart';
import '../../services/url_service.dart';
import '../../utils/theme_manager.dart';

/// 音源设置页面
/// 
/// 用户在此配置音源（获取歌曲播放 URL 的服务）
/// 支持 OmniParse（手动输入 URL）和洛雪音乐（导入 JS 脚本）两种音源类型
class AudioSourceSettings extends StatefulWidget {
  const AudioSourceSettings({super.key});

  @override
  State<AudioSourceSettings> createState() => _AudioSourceSettingsState();
}

class _AudioSourceSettingsState extends State<AudioSourceSettings> {
  // OmniParse 控制器
  final TextEditingController _urlController = TextEditingController();
  
  // 洛雪音源控制器
  final TextEditingController _lxScriptUrlController = TextEditingController();
  
  final AudioSourceService _audioSourceService = AudioSourceService();
  final LxMusicSourceParser _lxParser = LxMusicSourceParser();
  
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
    // 如果是洛雪音源，显示脚本来源
    if (_audioSourceService.sourceType == AudioSourceType.lxmusic) {
      _lxScriptUrlController.text = _audioSourceService.lxScriptSource;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _lxScriptUrlController.dispose();
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
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

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
    Navigator.of(context).pop();
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

      setState(() {
        _importResult = '导入成功：${config.name} v${config.version}';
        _importSuccess = true;
      });

      _showMessage('洛雪音源脚本导入成功');
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

      setState(() {
        _importResult = '导入成功：${config.name} v${config.version}';
        _importSuccess = true;
        _lxScriptUrlController.text = config.source;
      });

      _showMessage('洛雪音源脚本导入成功');
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
    setState(() {
      _testResult = null;
      _importResult = null;
    });
    _showMessage('音源配置已清除');
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
    } else if (themeManager.isCupertinoFramework && (Platform.isIOS || Platform.isAndroid)) {
      return _buildCupertinoContent(context);
    } else {
      return _buildMaterialContent(context);
    }
  }

  /// Fluent UI 风格 (Windows)
  Widget _buildFluentContent(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    
    return fluent.ScaffoldPage(
      header: fluent.PageHeader(
        title: const Text('音源设置'),
        leading: fluent.IconButton(
          icon: const Icon(fluent.FluentIcons.back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      content: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      '音源是用于获取歌曲播放链接的服务。由于法律原因，应用不内置音源，'
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
            fluent.ComboBox<AudioSourceType>(
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
        ),
      ),
    );
  }

  /// Cupertino 风格 (iOS/Android)
  Widget _buildCupertinoContent(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('音源设置'),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(CupertinoIcons.back),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 说明卡片
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground.resolveFrom(context),
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
                        style: CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '音源是用于获取歌曲播放链接的服务。由于法律原因，应用不内置音源，'
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
                      ? const Icon(CupertinoIcons.checkmark, color: CupertinoColors.activeBlue)
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
                footer: const Text('输入洛雪音源脚本的 URL 链接，或点击下方按钮从本地导入'),
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
                        onPressed: _isImporting ? null : _importLxScriptFromUrl,
                        child: _isImporting
                            ? const CupertinoActivityIndicator()
                            : const Text('从链接导入'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        onPressed: _isImporting ? null : _importLxScriptFromFile,
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
                          style: TextStyle(color: CupertinoColors.destructiveRed),
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
                          style: TextStyle(color: CupertinoColors.destructiveRed),
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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('音源设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      '音源是用于获取歌曲播放链接的服务。由于法律原因，应用不内置音源，'
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
            DropdownButtonFormField<AudioSourceType>(
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
        ),
      ),
    );
  }

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

  /// 当前是否选择了洛雪音源类型
  bool get _isLxMusicSelected => _audioSourceService.sourceType == AudioSourceType.lxmusic;

  /// 当前是否选择了 TuneHub 音源类型
  bool get _isTuneHubSelected => _audioSourceService.sourceType == AudioSourceType.tunehub;

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
}

/// 显示音源未配置提示
/// 
/// 当用户尝试播放歌曲但未配置音源时调用此函数
/// 使用 SnackBar 而非对话框，避免 Navigator context 问题
/// 注意：Fluent UI 也使用 SnackBar，因为 displayInfoBar 需要 ScaffoldPage 层级
void showAudioSourceNotConfiguredDialog(BuildContext context) {
  print('🔔 [AudioSourceSettings] showAudioSourceNotConfiguredDialog 被调用');
  
  // 检查 context 是否有效
  if (!context.mounted) {
    print('⚠️ [AudioSourceSettings] context 已失效');
    return;
  }
  
  final themeManager = ThemeManager();
  
  try {
    // 所有平台统一使用 ScaffoldMessenger.showSnackBar
    // 因为它不需要特定的widget层级，可以在任何有Scaffold的地方显示
    print('🔔 [AudioSourceSettings] 显示 SnackBar 提示');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('未配置音源，无法播放在线音乐。请前往设置页面配置音源服务地址。'),
        duration: const Duration(seconds: 5),
        backgroundColor: themeManager.isFluentFramework 
            ? const Color(0xFF2B5278)  // Fluent UI 警告色
            : null,
        action: SnackBarAction(
          label: '前往设置',
          textColor: themeManager.isFluentFramework
              ? Colors.white
              : null,
          onPressed: () {
            if (themeManager.isFluentFramework && Platform.isWindows) {
              Navigator.of(context).push(
                fluent.FluentPageRoute(
                  builder: (context) => const AudioSourceSettings(),
                ),
              );
            } else if (themeManager.isCupertinoFramework && (Platform.isIOS || Platform.isAndroid)) {
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (context) => const AudioSourceSettings(),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AudioSourceSettings(),
                ),
              );
            }
          },
        ),
      ),
    );
    print('✅ [AudioSourceSettings] SnackBar 已显示');
  } catch (e, stack) {
    print('❌ [AudioSourceSettings] 显示提示失败: $e');
    print('❌ [AudioSourceSettings] Stack: $stack');
  }
}
