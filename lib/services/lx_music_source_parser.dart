import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

/// 洛雪音源脚本配置
/// 
/// 从洛雪音源 JS 脚本中解析出的配置信息
class LxMusicSourceConfig {
  /// 音源名称
  final String name;
  
  /// 音源版本
  final String version;
  
  /// API 基础 URL
  final String apiUrl;
  
  /// API 验证密钥
  final String apiKey;
  
  /// 脚本来源（URL 或文件路径）
  final String source;
  
  /// URL 路径模板（用于构建请求 URL）
  final String urlPathTemplate;

  LxMusicSourceConfig({
    required this.name,
    required this.version,
    required this.apiUrl,
    required this.apiKey,
    required this.source,
    this.urlPathTemplate = '',
  });

  /// 检查配置是否有效
  /// 
  /// 至少需要有 API URL 才算有效配置
  bool get isValid => apiUrl.isNotEmpty;
}

/// 洛雪音源脚本解析器
/// 
/// 用于解析洛雪音源 JS 脚本，提取 API 配置信息
class LxMusicSourceParser {
  /// 从 URL 解析洛雪音源脚本
  /// 
  /// [scriptUrl] - 脚本的 URL 地址
  /// 
  /// 返回解析后的配置，如果解析失败返回 null
  Future<LxMusicSourceConfig?> parseFromUrl(String scriptUrl) async {
    try {
      print('🔍 [LxMusicSourceParser] 从 URL 解析脚本: $scriptUrl');
      
      // 下载脚本内容
      final response = await http.get(
        Uri.parse(scriptUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        print('❌ [LxMusicSourceParser] 下载脚本失败: HTTP ${response.statusCode}');
        return null;
      }

      final scriptContent = response.body;
      print('✅ [LxMusicSourceParser] 脚本下载成功，长度: ${scriptContent.length}');

      // 解析脚本内容
      final config = _parseScriptContent(scriptContent, scriptUrl);
      
      return config;
    } catch (e) {
      print('❌ [LxMusicSourceParser] 解析失败: $e');
      return null;
    }
  }

  /// 从本地文件解析洛雪音源脚本
  /// 
  /// 打开文件选择器让用户选择 .js 文件
  /// 
  /// 返回解析后的配置，如果用户取消或解析失败返回 null
  Future<LxMusicSourceConfig?> parseFromFile() async {
    try {
      print('🔍 [LxMusicSourceParser] 从本地文件解析脚本');
      
      // 打开文件选择器
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['js'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        print('⚠️ [LxMusicSourceParser] 用户取消了文件选择');
        return null;
      }

      final file = result.files.first;
      String? scriptContent;
      String source;

      if (file.path != null) {
        // 桌面平台：直接读取文件
        scriptContent = await File(file.path!).readAsString();
        source = file.path!;
      } else if (file.bytes != null) {
        // Web/移动平台：从字节读取
        scriptContent = String.fromCharCodes(file.bytes!);
        source = file.name;
      } else {
        print('❌ [LxMusicSourceParser] 无法读取文件内容');
        return null;
      }

      print('✅ [LxMusicSourceParser] 文件读取成功: ${file.name}，长度: ${scriptContent.length}');

      // 解析脚本内容
      final config = _parseScriptContent(scriptContent, source);
      
      return config;
    } catch (e) {
      print('❌ [LxMusicSourceParser] 解析失败: $e');
      return null;
    }
  }

  /// 解析脚本内容
  /// 
  /// 从 JS 脚本中提取配置信息
  LxMusicSourceConfig? _parseScriptContent(String scriptContent, String source) {
    try {
      print('🔍 [LxMusicSourceParser] 开始解析脚本内容...');

      // 提取名称
      String name = _extractName(scriptContent);
      
      // 提取版本
      String version = _extractVersion(scriptContent);
      
      // 提取 API URL
      String apiUrl = _extractApiUrl(scriptContent);
      
      // 提取 API Key
      String apiKey = _extractApiKey(scriptContent);
      
      // 提取 URL 路径模板
      String urlPathTemplate = _extractUrlPathTemplate(scriptContent);

      print('📋 [LxMusicSourceParser] 解析结果:');
      print('   名称: $name');
      print('   版本: $version');
      print('   API URL: $apiUrl');
      print('   API Key: ${apiKey.isNotEmpty ? "(已提取)" : "(未找到)"}');
      print('   路径模板: ${urlPathTemplate.isNotEmpty ? urlPathTemplate : "(未找到)"}');

      return LxMusicSourceConfig(
        name: name,
        version: version,
        apiUrl: apiUrl,
        apiKey: apiKey,
        source: source,
        urlPathTemplate: urlPathTemplate,
      );
    } catch (e) {
      print('❌ [LxMusicSourceParser] 解析脚本内容失败: $e');
      return null;
    }
  }

  /// 提取音源名称
  String _extractName(String script) {
    // 尝试匹配 name: 'xxx' 或 name: "xxx"
    final namePatterns = [
      RegExp(r'''name\s*:\s*['"]([^'"]+)['"]'''),
      RegExp(r'''['"]name['"]\s*:\s*['"]([^'"]+)['"]'''),
      RegExp(r'''"name"\s*:\s*"([^"]+)"'''),
    ];

    for (final pattern in namePatterns) {
      final match = pattern.firstMatch(script);
      if (match != null) {
        return match.group(1) ?? '未知音源';
      }
    }

    return '洛雪音源';
  }

  /// 提取版本号
  String _extractVersion(String script) {
    // 尝试匹配 version: 'xxx' 或 version: "xxx"
    final versionPatterns = [
      RegExp(r'''version\s*:\s*['"]([^'"]+)['"]'''),
      RegExp(r'''['"]version['"]\s*:\s*['"]([^'"]+)['"]'''),
      RegExp(r'''"version"\s*:\s*"([^"]+)"'''),
    ];

    for (final pattern in versionPatterns) {
      final match = pattern.firstMatch(script);
      if (match != null) {
        return match.group(1) ?? '1.0.0';
      }
    }

    return '1.0.0';
  }

  /// 提取 API URL
  String _extractApiUrl(String script) {
    // 常见的 API URL 提取模式
    final urlPatterns = [
      // 直接匹配 http/https URL
      RegExp(r'''['"]?(https?://[a-zA-Z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+)['"]?'''),
      // 匹配 apiUrl 或 api_url 变量
      RegExp(r'''apiUrl\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''api[_-]?url\s*[:=]\s*['"]([^'"]+)['"]'''),
      // 匹配 host 变量
      RegExp(r'''host\s*[:=]\s*['"]([^'"]+)['"]'''),
      // 匹配 baseUrl
      RegExp(r'''baseUrl\s*[:=]\s*['"]([^'"]+)['"]'''),
    ];

    for (final pattern in urlPatterns) {
      final matches = pattern.allMatches(script);
      for (final match in matches) {
        final url = match.group(1);
        if (url != null && _isValidApiUrl(url)) {
          return url;
        }
      }
    }

    return '';
  }

  /// 验证是否为有效的 API URL
  bool _isValidApiUrl(String url) {
    // 过滤掉明显不是 API URL 的地址
    final excludePatterns = [
      'github.com',
      'jsdelivr.net',
      'cdnjs.com',
      'unpkg.com',
      'example.com',
      'localhost',
    ];

    for (final pattern in excludePatterns) {
      if (url.contains(pattern)) {
        return false;
      }
    }

    // 必须是 http:// 或 https:// 开头
    return url.startsWith('http://') || url.startsWith('https://');
  }

  /// 提取 API Key
  String _extractApiKey(String script) {
    // 尝试匹配各种 API Key 模式
    final keyPatterns = [
      RegExp(r'''apiKey\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''api[_-]?key\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''key\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''token\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''['"]key['"]\s*:\s*['"]([^'"]+)['"]'''),
    ];

    for (final pattern in keyPatterns) {
      final match = pattern.firstMatch(script);
      if (match != null) {
        final key = match.group(1);
        // 过滤掉明显不是 API Key 的值
        if (key != null && key.length > 2 && !key.contains(' ')) {
          return key;
        }
      }
    }

    return '';
  }

  /// 提取 URL 路径模板
  String _extractUrlPathTemplate(String script) {
    // 尝试匹配 URL 路径模板
    final templatePatterns = [
      // 匹配类似 /url/{source}/{songId}/{quality} 的模板
      RegExp(r'''/url/\{?[a-zA-Z]+\}?/\{?[a-zA-Z]+\}?/\{?[a-zA-Z]+\}?'''),
      // 匹配 path 或 urlPath 变量
      RegExp(r'''urlPath\s*[:=]\s*['"]([^'"]+)['"]'''),
      RegExp(r'''path\s*[:=]\s*['"]([^'"]+)['"]'''),
    ];

    for (final pattern in templatePatterns) {
      final match = pattern.firstMatch(script);
      if (match != null) {
        return match.group(0) ?? '';
      }
    }

    // 默认模板
    return '/url/{source}/{songId}/{quality}';
  }
}
