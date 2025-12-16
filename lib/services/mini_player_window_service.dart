import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 迷你播放器窗口服务
/// 管理桌面端窗口在正常模式和迷你播放器模式之间的切换
class MiniPlayerWindowService extends ChangeNotifier {
  static final MiniPlayerWindowService _instance = MiniPlayerWindowService._internal();
  factory MiniPlayerWindowService() => _instance;
  MiniPlayerWindowService._internal();

  // 窗口状态
  bool _isMiniMode = false;
  
  // 保存正常模式下的窗口尺寸和位置，用于恢复
  Size? _normalSize;
  Offset? _normalPosition;
  bool? _wasMaximized;
  
  // 迷你播放器窗口尺寸（参考 Apple Music 迷你播放器）
  static const Size miniPlayerSize = Size(360, 160);
  static const Size miniPlayerMinSize = Size(320, 140);
  
  // 正常窗口最小尺寸
  static const Size normalMinSize = Size(320, 120);
  
  /// 是否处于迷你播放器模式
  bool get isMiniMode => _isMiniMode;
  
  /// 切换到迷你播放器模式
  Future<void> enterMiniMode() async {
    if (_isMiniMode || !Platform.isWindows) return;
    
    try {
      // 保存当前窗口状态
      _wasMaximized = await windowManager.isMaximized();
      
      // 如果是最大化状态，先还原
      if (_wasMaximized == true) {
        await windowManager.unmaximize();
        // 等待窗口还原完成
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      // 保存当前窗口尺寸和位置
      _normalSize = await windowManager.getSize();
      _normalPosition = await windowManager.getPosition();
      
      print('📐 [MiniPlayerWindow] 保存正常窗口状态: size=$_normalSize, position=$_normalPosition, wasMaximized=$_wasMaximized');
      
      // 设置迷你播放器的最小尺寸
      await windowManager.setMinimumSize(miniPlayerMinSize);
      
      // 计算迷你播放器位置（屏幕右下角）
      // 获取当前窗口位置，将迷你窗口放在原窗口的右下角附近
      final newPosition = Offset(
        _normalPosition!.dx + (_normalSize!.width - miniPlayerSize.width) / 2,
        _normalPosition!.dy + (_normalSize!.height - miniPlayerSize.height) / 2,
      );
      
      // 设置窗口尺寸和位置
      await windowManager.setSize(miniPlayerSize);
      await windowManager.setPosition(newPosition);
      
      // 设置窗口始终置顶
      await windowManager.setAlwaysOnTop(true);
      
      // 禁用最大化
      await windowManager.setMaximizable(false);
      
      _isMiniMode = true;
      notifyListeners();
      
      print('✅ [MiniPlayerWindow] 已进入迷你播放器模式');
    } catch (e) {
      print('❌ [MiniPlayerWindow] 进入迷你模式失败: $e');
    }
  }
  
  /// 退出迷你播放器模式，恢复正常窗口
  Future<void> exitMiniMode() async {
    if (!_isMiniMode || !Platform.isWindows) return;
    
    try {
      // 先更新状态，让 UI 切换回主布局
      _isMiniMode = false;
      notifyListeners();
      
      // 然后执行窗口操作，给 UI 足够的时间完成重建
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 取消置顶
      await windowManager.setAlwaysOnTop(false);
      
      // 恢复最大化功能
      await windowManager.setMaximizable(true);
      
      // 恢复正常窗口最小尺寸
      await windowManager.setMinimumSize(normalMinSize);
      
      // 恢复窗口尺寸和位置
      if (_normalSize != null) {
        await windowManager.setSize(_normalSize!);
      }
      if (_normalPosition != null) {
        await windowManager.setPosition(_normalPosition!);
      }
      
      // 如果之前是最大化状态，恢复最大化
      if (_wasMaximized == true) {
        await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.maximize();
      }
      
      print('✅ [MiniPlayerWindow] 已退出迷你播放器模式');
    } catch (e) {
      print('❌ [MiniPlayerWindow] 退出迷你模式失败: $e');
    }
  }
  
  /// 切换迷你播放器模式
  Future<void> toggleMiniMode() async {
    if (_isMiniMode) {
      await exitMiniMode();
    } else {
      await enterMiniMode();
    }
  }
}
