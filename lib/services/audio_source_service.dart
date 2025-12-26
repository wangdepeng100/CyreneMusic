import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/song_detail.dart';

/// 音源类型枚举
enum AudioSourceType {
  omniparse,   // OmniParse 音源（兼容现有后端格式）
  lxmusic,     // 洛雪音乐音源
  tunehub,     // TuneHub 音源（公开 API）
}

/// 音源服务 - 管理音源配置（获取歌曲播放 URL）
/// 
/// 音源与后端服务分离：
/// - 后端服务（UrlService）：负责搜索、歌单导入、用户系统、歌词等
/// - 音源服务（AudioSourceService）：负责获取歌曲播放 URL
/// 
/// 这样设计是为了规避法律风险，用户需要自行配置音源。
class AudioSourceService extends ChangeNotifier {
  static final AudioSourceService _instance = AudioSourceService._internal();
  factory AudioSourceService() => _instance;
  AudioSourceService._internal();

  /// 音源类型
  AudioSourceType _sourceType = AudioSourceType.omniparse;

  /// 音源 URL
  String _sourceUrl = '';

  /// 洛雪音源验证密钥
  String _lxApiKey = '';

  /// 洛雪音源名称（从脚本解析）
  String _lxSourceName = '';

  /// 洛雪音源版本（从脚本解析）
  String _lxSourceVersion = '';

  /// 洛雪音源脚本来源（URL 或文件名）
  String _lxScriptSource = '';
  
  /// 洛雪音源 URL 路径模板
  /// 例如: "/url/{source}/{songId}/{quality}" 或 "/v1/urlinfo/{songId}/{quality}"
  String _lxUrlPathTemplate = '';

  /// 是否已初始化
  bool _isInitialized = false;

  // ==================== 存储键名 ====================
  static const String _keySourceType = 'audio_source_type';
  static const String _keySourceUrl = 'audio_source_url';
  static const String _keyLxApiKey = 'audio_source_lx_api_key';
  static const String _keyLxSourceName = 'audio_source_lx_name';
  static const String _keyLxSourceVersion = 'audio_source_lx_version';
  static const String _keyLxScriptSource = 'audio_source_lx_script_source';
  static const String _keyLxUrlPathTemplate = 'audio_source_lx_url_path_template';

  // ==================== 洛雪音源来源代码映射 ====================
  /// MusicSource 到洛雪音源来源代码的映射
  static const Map<MusicSource, String> _lxSourceCodeMap = {
    MusicSource.netease: 'wy',  // 网易云音乐
    MusicSource.qq: 'tx',       // QQ音乐（腾讯）
    MusicSource.kugou: 'kg',    // 酷狗音乐
    MusicSource.kuwo: 'kw',     // 酷我音乐
    // MusicSource.migu: 'mg',  // 咪咕音乐（暂不支持）
    // MusicSource.apple 不支持洛雪音源
  };

  /// 洛雪音源支持的音质列表
  static const List<String> lxQualityOptions = ['128k', '320k', 'flac', 'flac24bit'];

  // ==================== TuneHub 音源来源代码映射 ====================
  /// MusicSource 到 TuneHub 音源来源代码的映射
  static const Map<MusicSource, String> _tuneHubSourceCodeMap = {
    MusicSource.netease: 'netease',  // 网易云音乐
    MusicSource.qq: 'qq',            // QQ音乐
    MusicSource.kuwo: 'kuwo',        // 酷我音乐
    // TuneHub 不支持酷狗、Apple Music
  };

  /// TuneHub 音源支持的音质列表
  static const List<String> tuneHubQualityOptions = ['128k', '320k', 'flac', 'flac24bit'];

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) {
      print('⚠️ [AudioSourceService] 已经初始化，跳过重复初始化');
      return;
    }

    await _loadSettings();
    _isInitialized = true;
    print('✅ [AudioSourceService] 初始化完成');
  }

  /// 从本地存储加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 加载音源类型
      final sourceTypeIndex = prefs.getInt(_keySourceType) ?? 0;
      if (sourceTypeIndex >= 0 && sourceTypeIndex < AudioSourceType.values.length) {
        _sourceType = AudioSourceType.values[sourceTypeIndex];
      }

      // 加载音源 URL
      _sourceUrl = prefs.getString(_keySourceUrl) ?? '';

      // 加载洛雪 API Key
      _lxApiKey = prefs.getString(_keyLxApiKey) ?? '';

      // 加载洛雪音源脚本信息
      _lxSourceName = prefs.getString(_keyLxSourceName) ?? '';
      _lxSourceVersion = prefs.getString(_keyLxSourceVersion) ?? '';
      _lxScriptSource = prefs.getString(_keyLxScriptSource) ?? '';
      _lxUrlPathTemplate = prefs.getString(_keyLxUrlPathTemplate) ?? '';

      print('🔊 [AudioSourceService] 从本地加载配置:');
      print('   音源类型: ${_sourceType.name}');
      print('   音源 URL: ${_sourceUrl.isNotEmpty ? _sourceUrl : "(未配置)"}');
      if (_sourceType == AudioSourceType.lxmusic) {
        print('   洛雪音源: ${_lxSourceName.isNotEmpty ? _lxSourceName : "(未知)"} v$_lxSourceVersion');
        print('   脚本来源: ${_lxScriptSource.isNotEmpty ? _lxScriptSource : "(未知)"}');
        print('   路径模板: ${_lxUrlPathTemplate.isNotEmpty ? _lxUrlPathTemplate : "(默认)"}');
        print('   API Key: ${_lxApiKey.isNotEmpty ? "(已配置)" : "(未配置)"}');
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ [AudioSourceService] 加载配置失败: $e');
    }
  }

  /// 保存音源类型
  Future<void> _saveSourceType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keySourceType, _sourceType.index);
      print('💾 [AudioSourceService] 音源类型已保存: ${_sourceType.name}');
    } catch (e) {
      print('❌ [AudioSourceService] 保存音源类型失败: $e');
    }
  }

  /// 保存音源 URL
  Future<void> _saveSourceUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySourceUrl, _sourceUrl);
      print('💾 [AudioSourceService] 音源 URL 已保存: $_sourceUrl');
    } catch (e) {
      print('❌ [AudioSourceService] 保存音源 URL 失败: $e');
    }
  }

  /// 保存洛雪 API Key
  Future<void> _saveLxApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLxApiKey, _lxApiKey);
      print('💾 [AudioSourceService] 洛雪 API Key 已保存');
    } catch (e) {
      print('❌ [AudioSourceService] 保存洛雪 API Key 失败: $e');
    }
  }

  /// 保存洛雪脚本信息
  Future<void> _saveLxScriptInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLxSourceName, _lxSourceName);
      await prefs.setString(_keyLxSourceVersion, _lxSourceVersion);
      await prefs.setString(_keyLxScriptSource, _lxScriptSource);
      await prefs.setString(_keyLxUrlPathTemplate, _lxUrlPathTemplate);
      print('💾 [AudioSourceService] 洛雪脚本信息已保存');
    } catch (e) {
      print('❌ [AudioSourceService] 保存洛雪脚本信息失败: $e');
    }
  }

  // ==================== Getters ====================

  /// 获取当前音源类型
  AudioSourceType get sourceType => _sourceType;

  /// 获取当前音源 URL
  String get sourceUrl => _sourceUrl;

  /// 获取洛雪 API Key
  String get lxApiKey => _lxApiKey;

  /// 获取洛雪音源名称
  String get lxSourceName => _lxSourceName;

  /// 获取洛雪音源版本
  String get lxSourceVersion => _lxSourceVersion;

  /// 获取洛雪脚本来源
  String get lxScriptSource => _lxScriptSource;

  /// 音源是否已配置
  bool get isConfigured => _sourceUrl.isNotEmpty;

  /// 获取音源基础 URL（移除末尾斜杠）
  String get baseUrl {
    if (_sourceUrl.isEmpty) return '';
    return _sourceUrl.endsWith('/') 
        ? _sourceUrl.substring(0, _sourceUrl.length - 1) 
        : _sourceUrl;
  }

  // ==================== Setters ====================

  /// 设置音源类型
  void setSourceType(AudioSourceType type) {
    if (_sourceType != type) {
      _sourceType = type;
      _saveSourceType();
      notifyListeners();
      print('🔊 [AudioSourceService] 音源类型已更改为: ${type.name}');
    }
  }

  /// 设置音源 URL
  void setSourceUrl(String url) {
    // 清理 URL
    final cleanUrl = url.trim().endsWith('/')
        ? url.trim().substring(0, url.trim().length - 1)
        : url.trim();

    if (_sourceUrl != cleanUrl) {
      _sourceUrl = cleanUrl;
      _saveSourceUrl();
      notifyListeners();
      print('🔊 [AudioSourceService] 音源 URL 已更改为: $cleanUrl');
    }
  }

  /// 设置洛雪 API Key
  void setLxApiKey(String key) {
    final cleanKey = key.trim();
    if (_lxApiKey != cleanKey) {
      _lxApiKey = cleanKey;
      _saveLxApiKey();
      notifyListeners();
      print('🔊 [AudioSourceService] 洛雪 API Key 已更改');
    }
  }

  /// 配置音源（同时设置类型和 URL）
  void configure(AudioSourceType type, String url, {String? lxApiKey}) {
    setSourceType(type);
    setSourceUrl(url);
    if (lxApiKey != null) {
      setLxApiKey(lxApiKey);
    }
  }

  /// 从解析的洛雪脚本配置导入
  /// 
  /// 参数:
  /// - name: 音源名称
  /// - version: 音源版本
  /// - apiUrl: API 基础 URL
  /// - apiKey: API 验证密钥
  /// - scriptSource: 脚本来源（URL 或文件名）
  /// - urlPathTemplate: URL 路径模板（可选）
  void configureLxMusicSource({
    required String name,
    required String version,
    required String apiUrl,
    required String apiKey,
    required String scriptSource,
    String? urlPathTemplate,
  }) {
    print('🎵 [AudioSourceService] 导入洛雪音源脚本:');
    print('   名称: $name');
    print('   版本: $version');
    print('   API URL: $apiUrl');
    print('   路径模板: ${urlPathTemplate ?? "(默认)"}');
    print('   来源: $scriptSource');

    _sourceType = AudioSourceType.lxmusic;
    _sourceUrl = apiUrl.trim().endsWith('/') 
        ? apiUrl.trim().substring(0, apiUrl.trim().length - 1)
        : apiUrl.trim();
    _lxApiKey = apiKey.trim();
    _lxSourceName = name;
    _lxSourceVersion = version;
    _lxScriptSource = scriptSource;
    _lxUrlPathTemplate = urlPathTemplate ?? '';

    _saveSourceType();
    _saveSourceUrl();
    _saveLxApiKey();
    _saveLxScriptInfo();
    
    notifyListeners();
    print('✅ [AudioSourceService] 洛雪音源配置完成');
  }

  /// 清除音源配置
  void clear() {
    _sourceUrl = '';
    _lxApiKey = '';
    _lxSourceName = '';
    _lxSourceVersion = '';
    _lxScriptSource = '';
    _lxUrlPathTemplate = '';
    _saveSourceUrl();
    _saveLxApiKey();
    _saveLxScriptInfo();
    notifyListeners();
    print('🗑️ [AudioSourceService] 音源配置已清除');
  }

  // ==================== 洛雪音源支持 ====================

  /// 检查 MusicSource 是否支持洛雪音源
  bool isLxSourceSupported(MusicSource source) {
    return _lxSourceCodeMap.containsKey(source);
  }

  /// 获取洛雪音源来源代码
  String? getLxSourceCode(MusicSource source) {
    return _lxSourceCodeMap[source];
  }

  /// 将 AudioQuality 转换为洛雪音质参数
  String getLxQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard:
        return '128k';
      case AudioQuality.exhigh:
        return '320k';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
      case AudioQuality.jymaster:
        return 'flac24bit';
      default:
        return '320k';
    }
  }

  /// 构建洛雪音源请求 URL
  /// 
  /// 如果有从脚本解析得到的路径模板，使用模板构建；
  /// 否则使用默认格式: ${baseUrl}/url/${source}/${songId}/${quality}
  String buildLxMusicUrl(MusicSource source, dynamic songId, AudioQuality quality) {
    final sourceCode = getLxSourceCode(source);
    if (sourceCode == null) {
      throw UnsupportedError('洛雪音源不支持 ${source.name}');
    }
    final lxQuality = getLxQuality(quality);
    
    // 如果有路径模板，使用模板构建 URL
    if (_lxUrlPathTemplate.isNotEmpty) {
      final path = _lxUrlPathTemplate
          .replaceAll('{source}', sourceCode)
          .replaceAll('{songId}', songId.toString())
          .replaceAll('{quality}', lxQuality);
      print('🔗 [AudioSourceService] 使用路径模板构建 URL: $baseUrl$path');
      return '$baseUrl$path';
    }
    
    // 默认格式
    return '$baseUrl/url/$sourceCode/$songId/$lxQuality';
  }

  /// 获取洛雪音源请求头
  Map<String, String> getLxRequestHeaders() {
    return {
      'Content-Type': 'application/json',
      'User-Agent': 'lx-music-request/1.0.0',
      if (_lxApiKey.isNotEmpty) 'X-Request-Key': _lxApiKey,
    };
  }

  // ==================== API 端点（OmniParse 格式）====================

  /// 获取网易云歌曲 URL 端点
  String get neteaseSongUrl => isConfigured ? '$baseUrl/song' : '';

  /// 获取 QQ 音乐歌曲 URL 端点
  String get qqSongUrl => isConfigured ? '$baseUrl/qq/song' : '';

  /// 获取酷狗歌曲 URL 端点
  String get kugouSongUrl => isConfigured ? '$baseUrl/kugou/song' : '';

  /// 获取酷我歌曲 URL 端点
  String get kuwoSongUrl => isConfigured ? '$baseUrl/kuwo/song' : '';

  /// 获取 Apple Music 歌曲 URL 端点
  String get appleSongUrl => isConfigured ? '$baseUrl/apple/song' : '';

  /// 获取 Apple Music 流端点
  String get appleStreamUrl => isConfigured ? '$baseUrl/apple/stream' : '';

  /// 获取音频代理端点（用于移动端）
  String get audioProxyUrl => isConfigured ? '$baseUrl/audio/proxy' : '';

  // ==================== 工具方法 ====================

  /// 验证 URL 格式
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;

    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 获取音源类型显示名称
  String getSourceTypeName() {
    switch (_sourceType) {
      case AudioSourceType.omniparse:
        return 'OmniParse';
      case AudioSourceType.lxmusic:
        return '洛雪音乐';
      case AudioSourceType.tunehub:
        return 'TuneHub';
    }
  }

  /// 获取音源配置描述
  String getSourceDescription() {
    if (!isConfigured) {
      return '未配置音源';
    }
    if (_sourceType == AudioSourceType.lxmusic) {
      return '${getSourceTypeName()} ($baseUrl) ${_lxApiKey.isNotEmpty ? "[已认证]" : "[无密钥]"}';
    }
    return '${getSourceTypeName()} ($baseUrl)';
  }

  // ==================== TuneHub 音源支持 ====================

  /// 检查 MusicSource 是否支持 TuneHub 音源
  bool isTuneHubSourceSupported(MusicSource source) {
    return _tuneHubSourceCodeMap.containsKey(source);
  }

  /// 获取 TuneHub 音源来源代码
  String? getTuneHubSourceCode(MusicSource source) {
    return _tuneHubSourceCodeMap[source];
  }

  /// 将 AudioQuality 转换为 TuneHub 音质参数
  String getTuneHubQuality(AudioQuality quality) {
    switch (quality) {
      case AudioQuality.standard:
        return '128k';
      case AudioQuality.exhigh:
        return '320k';
      case AudioQuality.lossless:
        return 'flac';
      case AudioQuality.hires:
      case AudioQuality.jymaster:
        return 'flac24bit';
      default:
        return '320k';
    }
  }

  /// 构建 TuneHub 音源请求 URL（获取歌曲详情）
  /// 格式: ${baseUrl}/api/?type=info&source=${source}&id=${songId}
  String buildTuneHubInfoUrl(MusicSource source, dynamic songId) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) {
      throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    }
    return '$baseUrl/api/?type=info&source=$sourceCode&id=$songId';
  }

  /// 构建 TuneHub 音源播放 URL
  /// 格式: ${baseUrl}/api/?type=url&source=${source}&id=${songId}&br=${quality}
  String buildTuneHubMusicUrl(MusicSource source, dynamic songId, AudioQuality quality) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) {
      throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    }
    final tuneHubQuality = getTuneHubQuality(quality);
    return '$baseUrl/api/?type=url&source=$sourceCode&id=$songId&br=$tuneHubQuality';
  }

  /// 构建 TuneHub 歌词请求 URL
  /// 格式: ${baseUrl}/api/?type=lrc&source=${source}&id=${songId}
  String buildTuneHubLyricUrl(MusicSource source, dynamic songId) {
    final sourceCode = getTuneHubSourceCode(source);
    if (sourceCode == null) {
      throw UnsupportedError('TuneHub 音源不支持 ${source.name}');
    }
    return '$baseUrl/api/?type=lrc&source=$sourceCode&id=$songId';
  }
}
