import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 歌词样式类型
enum LyricStyle {
  /// 默认样式 (卡拉OK样式)
  defaultStyle,
  
  /// 流体云样式
  fluidCloud,
}

/// 歌词对齐方式
enum LyricAlignment {
  /// 居中
  center,
  /// 顶部
  top,
}

/// 歌词样式服务
/// 管理歌词样式偏好设置
class LyricStyleService extends ChangeNotifier {
  static final LyricStyleService _instance = LyricStyleService._internal();
  factory LyricStyleService() => _instance;
  LyricStyleService._internal();

  static const String _storageKey = 'lyric_style';
  static const String _alignmentStorageKey = 'lyric_alignment';
  
  LyricStyle _currentStyle = LyricStyle.defaultStyle;
  LyricAlignment _currentAlignment = LyricAlignment.center;

  /// 获取当前歌词样式
  LyricStyle get currentStyle => _currentStyle;
  
  /// 获取当前歌词对齐方式
  LyricAlignment get currentAlignment => _currentAlignment;

  /// 初始化服务
  Future<void> initialize() async {
    await _loadStyle();
  }

  /// 从本地存储加载样式设置
  Future<void> _loadStyle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 加载样式
      final savedStyleIndex = prefs.getInt(_storageKey);
      if (savedStyleIndex != null && savedStyleIndex >= 0 && savedStyleIndex < LyricStyle.values.length) {
        _currentStyle = LyricStyle.values[savedStyleIndex];
      } else {
        _currentStyle = LyricStyle.fluidCloud;
      }
      
      // 加载对齐方式
      final savedAlignmentIndex = prefs.getInt(_alignmentStorageKey);
      if (savedAlignmentIndex != null && savedAlignmentIndex >= 0 && savedAlignmentIndex < LyricAlignment.values.length) {
        _currentAlignment = LyricAlignment.values[savedAlignmentIndex];
      } else {
        _currentAlignment = LyricAlignment.center;
      }
      
      notifyListeners();
    } catch (e) {
      print('❌ [LyricStyleService] 加载歌词配置失败: $e');
      _currentStyle = LyricStyle.defaultStyle;
      _currentAlignment = LyricAlignment.center;
    }
  }

  /// 设置歌词样式
  Future<void> setStyle(LyricStyle style) async {
    if (_currentStyle == style) return;
    
    _currentStyle = style;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, style.index);
      print('✅ [LyricStyleService] 歌词样式已保存: ${_getStyleName(style)}');
    } catch (e) {
      print('❌ [LyricStyleService] 保存歌词样式失败: $e');
    }
  }

  /// 设置歌词对齐方式
  Future<void> setAlignment(LyricAlignment alignment) async {
    if (_currentAlignment == alignment) return;
    
    _currentAlignment = alignment;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_alignmentStorageKey, alignment.index);
      print('✅ [LyricStyleService] 歌词对齐已保存: ${alignment.name}');
    } catch (e) {
      print('❌ [LyricStyleService] 保存歌词对齐失败: $e');
    }
  }

  /// 获取样式的显示名称
  String getStyleName(LyricStyle style) => _getStyleName(style);

  static String _getStyleName(LyricStyle style) {
    switch (style) {
      case LyricStyle.defaultStyle:
        return '默认样式';
      case LyricStyle.fluidCloud:
        return '流体云';
    }
  }

  /// 获取样式的描述
  String getStyleDescription(LyricStyle style) {
    switch (style) {
      case LyricStyle.defaultStyle:
        return '经典卡拉OK效果，从左到右填充';
      case LyricStyle.fluidCloud:
        return '云朵般流动的歌词效果，柔和舒适';
    }
  }
}

