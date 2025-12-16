import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:window_manager/window_manager.dart';
import '../../services/sleep_timer_service.dart';
import '../../services/playback_mode_service.dart';
import '../../services/download_service.dart';
import '../../services/notification_service.dart';
import '../../services/lyric_style_service.dart';
import '../../services/lyric_font_service.dart';
import '../../services/player_background_service.dart';
import '../../services/mini_player_window_service.dart';
import '../../utils/theme_manager.dart';
import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../settings_page/player_background_dialog.dart';

/// 播放器窗口控制组件
/// 包含可拖动顶部栏和窗口控制按钮
class PlayerWindowControls extends StatelessWidget {
  final bool isMaximized;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onPlaybackModePressed;
  // 译文按钮相关
  final bool showTranslationButton;
  final bool showTranslation;
  final VoidCallback? onTranslationToggle;
  // 下载按钮相关
  final Track? currentTrack;
  final SongDetail? currentSong;

  const PlayerWindowControls({
    super.key,
    required this.isMaximized,
    required this.onBackPressed,
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onPlaybackModePressed,
    this.showTranslationButton = false,
    this.showTranslation = false,
    this.onTranslationToggle,
    this.currentTrack,
    this.currentSong,
  });

  @override
  Widget build(BuildContext context) {
    // Windows 平台使用可拖动区域
    if (Platform.isWindows) {
      return SizedBox(
        height: 56,
        child: Stack(
          children: [
            // 可拖动区域（整个顶部）
            Positioned.fill(
              child: MoveWindow(
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            // 左侧：返回按钮 + 更多按钮
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 返回按钮
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                    color: Colors.white,
                    onPressed: onBackPressed,
                    tooltip: '返回',
                  ),
                  const SizedBox(width: 4),
                  // 更多按钮（带悬浮菜单）
                  _MoreMenuButton(
                    onPlaylistPressed: onPlaylistPressed,
                    onSleepTimerPressed: onSleepTimerPressed,
                    onPlaybackModePressed: onPlaybackModePressed,
                  ),
                  // 译文按钮（只在非中文歌词且有翻译时显示）
                  if (showTranslationButton)
                    _TranslationButton(
                      showTranslation: showTranslation,
                      onToggle: onTranslationToggle,
                    ),
                  // 下载按钮
                  if (currentTrack != null && currentSong != null)
                    _DownloadButton(
                      track: currentTrack!,
                      song: currentSong!,
                    ),
                  // 迷你播放器按钮
                  _MiniPlayerButton(),
                ],
              ),
            ),
            // 右侧：窗口控制按钮
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: _buildWindowButtons(),
            ),
          ],
        ),
      );
    } else {
      // 其他平台使用普通容器
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 32),
              color: Colors.white,
              onPressed: onBackPressed,
            ),
          ],
        ),
      );
    }
  }

  /// 构建窗口控制按钮（最小化、最大化、关闭）
  Widget _buildWindowButtons() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildWindowButton(
          icon: Icons.remove,
          onPressed: () => appWindow.minimize(),
          tooltip: '最小化',
        ),
        _buildWindowButton(
          icon: isMaximized ? Icons.fullscreen_exit : Icons.crop_square,
          onPressed: () => appWindow.maximizeOrRestore(),
          tooltip: isMaximized ? '还原' : '最大化',
        ),
        _buildWindowButton(
          icon: Icons.close_rounded,
          onPressed: () => windowManager.close(),
          tooltip: '关闭',
          isClose: true,
        ),
      ],
    );
  }

  /// 构建单个窗口按钮
  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isClose = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          hoverColor: isClose ? Colors.red : Colors.white.withOpacity(0.1),
          child: Container(
            width: 48,
            height: 56,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 更多菜单按钮（带悬浮弹出框）
class _MoreMenuButton extends StatefulWidget {
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onPlaybackModePressed;

  const _MoreMenuButton({
    this.onPlaylistPressed,
    this.onSleepTimerPressed,
    this.onPlaybackModePressed,
  });

  @override
  State<_MoreMenuButton> createState() => _MoreMenuButtonState();
}

class _MoreMenuButtonState extends State<_MoreMenuButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  bool _isHovering = false;
  bool _isMenuHovering = false;

  void _showMenu() {
    if (_overlayEntry != null) return;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          child: MouseRegion(
            onEnter: (_) {
              _isMenuHovering = true;
            },
            onExit: (_) {
              _isMenuHovering = false;
              _hideMenuDelayed();
            },
            child: Material(
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                    child: _buildMenuContent(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }

  Widget _buildMenuContent() {
    return AnimatedBuilder(
      animation: Listenable.merge([SleepTimerService(), PlaybackModeService(), LyricStyleService(), LyricFontService()]),
      builder: (context, _) {
        final sleepTimer = SleepTimerService();
        final playbackMode = PlaybackModeService();
        final lyricStyle = LyricStyleService();
        final lyricFont = LyricFontService();
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 播放列表
            if (widget.onPlaylistPressed != null)
              _buildMenuItem(
                icon: Icons.queue_music_rounded,
                label: '播放列表',
                onTap: () {
                  _hideMenu();
                  widget.onPlaylistPressed!();
                },
              ),
            
            // 分隔线
            if (widget.onPlaylistPressed != null)
              Divider(
                height: 1,
                color: Colors.white.withOpacity(0.1),
              ),
            
            // 播放器主题
            _buildMenuItem(
              icon: lyricStyle.currentStyle == LyricStyle.fluidCloud 
                  ? Icons.water_drop_rounded 
                  : Icons.music_note_rounded,
              label: lyricStyle.currentStyle == LyricStyle.fluidCloud 
                  ? '播放器主题: 流体云' 
                  : '播放器主题: 经典',
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.white54,
                size: 18,
              ),
              onTap: () {
                // 切换播放器主题
                final newStyle = lyricStyle.currentStyle == LyricStyle.fluidCloud 
                    ? LyricStyle.defaultStyle 
                    : LyricStyle.fluidCloud;
                lyricStyle.setStyle(newStyle);
                _overlayEntry?.markNeedsBuild();
              },
            ),
            
            // 播放器背景
            _buildMenuItem(
              icon: Icons.wallpaper_rounded,
              label: '播放器背景: ${PlayerBackgroundService().getBackgroundTypeName()}',
              onTap: () {
                _hideMenu();
                _showBackgroundDialog(context);
              },
            ),
            
            // 歌词字体
            _buildMenuItem(
              icon: Icons.font_download_rounded,
              label: '歌词字体: ${lyricFont.currentFontName}',
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.white54,
                size: 18,
              ),
              onTap: () {
                _hideMenu();
                _showFontPicker(context);
              },
            ),
            
            // 分隔线
            Divider(
              height: 1,
              color: Colors.white.withOpacity(0.1),
            ),
            
            // 播放模式
            _buildMenuItem(
              icon: _getPlaybackModeIcon(playbackMode.currentMode),
              label: playbackMode.getModeName(),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.white54,
                size: 18,
              ),
              onTap: () {
                playbackMode.toggleMode();
                // 更新菜单显示
                _overlayEntry?.markNeedsBuild();
              },
            ),
            
            // 睡眠定时器
            _buildMenuItem(
              icon: sleepTimer.isActive ? Icons.schedule : Icons.schedule_outlined,
              label: sleepTimer.isActive 
                  ? '定时停止: ${sleepTimer.remainingTimeString}' 
                  : '睡眠定时器',
              iconColor: sleepTimer.isActive ? Colors.amber : null,
              onTap: () {
                _hideMenu();
                if (widget.onSleepTimerPressed != null) {
                  widget.onSleepTimerPressed!();
                }
              },
            ),
          ],
        );
      },
    );
  }
  
  void _showBackgroundDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => PlayerBackgroundDialog(
        onChanged: () {
          // 背景设置变化后刷新
        },
      ),
    );
  }
  
  void _showFontPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _LyricFontPickerDialog(),
    );
  }

  IconData _getPlaybackModeIcon(PlaybackMode mode) {
    switch (mode) {
      case PlaybackMode.sequential:
        return Icons.repeat_rounded;
      case PlaybackMode.repeatOne:
        return Icons.repeat_one_rounded;
      case PlaybackMode.shuffle:
        return Icons.shuffle_rounded;
    }
  }

  void _hideMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _hideMenuDelayed() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!_isHovering && !_isMenuHovering) {
        _hideMenu();
      }
    });
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    Color? iconColor,
  }) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.white.withOpacity(0.1),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? Colors.white.withOpacity(0.9),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideMenu();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovering = true);
          _showMenu();
        },
        onExit: (_) {
          setState(() => _isHovering = false);
          _hideMenuDelayed();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _isHovering ? Colors.white.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.more_horiz,
                color: Colors.white.withOpacity(0.8),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 译文按钮组件
class _TranslationButton extends StatelessWidget {
  final bool showTranslation;
  final VoidCallback? onToggle;

  const _TranslationButton({
    required this.showTranslation,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: showTranslation ? '隐藏译文' : '显示译文',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withOpacity(0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: showTranslation ? Colors.white.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Center(
              child: Text(
                '译',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatelessWidget {
  final Track track;
  final SongDetail song;

  const _DownloadButton({
    required this.track,
    required this.song,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DownloadService(),
      builder: (context, child) {
        final downloadService = DownloadService();
        final isDownloading = downloadService.downloadTasks.containsKey(
          '${track.source.name}_${track.id}'
        );
        
        return Tooltip(
          message: isDownloading ? '下载中...' : '下载',
          child: InkWell(
            onTap: isDownloading ? null : () => _handleDownload(context),
            borderRadius: BorderRadius.circular(8),
            hoverColor: Colors.white.withOpacity(0.1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Icon(
                isDownloading ? Icons.downloading_rounded : Icons.download_rounded,
                color: isDownloading ? Colors.white54 : Colors.white.withOpacity(0.8),
                size: 24,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDownload(BuildContext context) async {
    try {
      // 检查是否已下载
      final isDownloaded = await DownloadService().isDownloaded(track);
      
      if (isDownloaded) {
        // 已下载，通过通知告知用户
        await NotificationService().showNotification(
          id: DateTime.now().millisecondsSinceEpoch % 100000,
          title: '已下载',
          body: '${track.name} 已存在于下载目录中',
        );
        return;
      }

      // 开始下载（下载完成后会自动发送通知）
      await DownloadService().downloadSong(
        track,
        song,
        onProgress: (progress) {
          // 下载进度会通过 DownloadService 的 notifyListeners 自动更新UI
        },
      );
    } catch (e) {
      // 下载失败，通过通知告知用户
      await NotificationService().showNotification(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: '下载失败',
        body: '${track.name}: $e',
      );
    }
  }
}

/// 歌词字体选择对话框（自适应主题）
class _LyricFontPickerDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    
    // 根据主题选择不同的对话框样式
    if (themeManager.isFluentFramework) {
      return _buildFluentDialog(context);
    } else if (themeManager.isCupertinoFramework) {
      return _buildCupertinoDialog(context);
    }
    return _buildMaterialDialog(context);
  }
  
  // ========== Fluent UI 对话框 ==========
  Widget _buildFluentDialog(BuildContext context) {
    final fluentTheme = fluent.FluentTheme.of(context);
    
    return fluent.ContentDialog(
      title: const Row(
        children: [
          Icon(fluent.FluentIcons.font, size: 20),
          SizedBox(width: 8),
          Text('选择歌词字体'),
        ],
      ),
      constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
      content: AnimatedBuilder(
        animation: LyricFontService(),
        builder: (context, _) {
          final fontService = LyricFontService();
          return ListView.builder(
            shrinkWrap: true,
            itemCount: LyricFontService.presetFonts.length,
            itemBuilder: (context, index) {
              final font = LyricFontService.presetFonts[index];
              final isSelected = fontService.fontType == 'preset' && 
                  fontService.presetFontId == font.id;
              
              return fluent.ListTile.selectable(
                selected: isSelected,
                onPressed: () async {
                  await fontService.setPresetFont(font.id);
                  if (context.mounted) Navigator.pop(context);
                },
                leading: Text(
                  '字',
                  style: TextStyle(
                    fontFamily: font.fontFamily,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: fluentTheme.accentColor,
                  ),
                ),
                title: Text(
                  font.name,
                  style: TextStyle(fontFamily: font.fontFamily),
                ),
                subtitle: Text(font.description),
                trailing: isSelected 
                    ? Icon(fluent.FluentIcons.check_mark, 
                        color: fluentTheme.accentColor, size: 16)
                    : null,
              );
            },
          );
        },
      ),
      actions: [
        fluent.Button(
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(fluent.FluentIcons.fabric_folder, size: 16),
              SizedBox(width: 8),
              Text('自定义字体...'),
            ],
          ),
          onPressed: () async {
            final success = await LyricFontService().pickAndLoadCustomFont();
            if (success && context.mounted) Navigator.pop(context);
          },
        ),
        fluent.FilledButton(
          child: const Text('关闭'),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
  
  // ========== Cupertino 对话框 ==========
  Widget _buildCupertinoDialog(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: CupertinoActionSheet(
        title: const Text('选择歌词字体'),
        message: const Text('选择一个字体来显示歌词'),
        actions: [
          ...LyricFontService.presetFonts.map((font) {
            final fontService = LyricFontService();
            final isSelected = fontService.fontType == 'preset' && 
                fontService.presetFontId == font.id;
            
            return CupertinoActionSheetAction(
              onPressed: () async {
                await fontService.setPresetFont(font.id);
                if (context.mounted) Navigator.pop(context);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(CupertinoIcons.checkmark_alt, 
                          color: CupertinoColors.activeBlue, size: 18),
                    ),
                  Text(
                    font.name,
                    style: TextStyle(
                      fontFamily: font.fontFamily,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? CupertinoColors.activeBlue : null,
                    ),
                  ),
                ],
              ),
            );
          }),
          CupertinoActionSheetAction(
            onPressed: () async {
              final success = await LyricFontService().pickAndLoadCustomFont();
              if (success && context.mounted) Navigator.pop(context);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.folder, size: 18),
                SizedBox(width: 8),
                Text('选择自定义字体...'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ),
    );
  }
  
  // ========== Material 对话框 ==========
  Widget _buildMaterialDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Icon(Icons.font_download_rounded, 
                      color: colorScheme.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    '选择歌词字体',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            
            const Divider(height: 1),
            
            // 字体列表
            Flexible(
              child: AnimatedBuilder(
                animation: LyricFontService(),
                builder: (context, _) {
                  final fontService = LyricFontService();
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: LyricFontService.presetFonts.length,
                    itemBuilder: (context, index) {
                      final font = LyricFontService.presetFonts[index];
                      final isSelected = fontService.fontType == 'preset' && 
                          fontService.presetFontId == font.id;
                      
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: colorScheme.primaryContainer.withOpacity(0.3),
                        leading: CircleAvatar(
                          backgroundColor: isSelected 
                              ? colorScheme.primary 
                              : colorScheme.surfaceContainerHighest,
                          child: Text(
                            '字',
                            style: TextStyle(
                              fontFamily: font.fontFamily,
                              color: isSelected 
                                  ? colorScheme.onPrimary 
                                  : colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          font.name,
                          style: TextStyle(
                            fontFamily: font.fontFamily,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        subtitle: Text(font.description),
                        trailing: isSelected 
                            ? Icon(Icons.check_circle, color: colorScheme.primary)
                            : null,
                        onTap: () async {
                          await fontService.setPresetFont(font.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            
            const Divider(height: 1),
            
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final success = await LyricFontService().pickAndLoadCustomFont();
                      if (success && context.mounted) Navigator.pop(context);
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('自定义字体'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 迷你播放器按钮
class _MiniPlayerButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '迷你播放器',
      child: IconButton(
        icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 20),
        color: Colors.white.withOpacity(0.9),
        onPressed: () {
          // 先关闭全屏播放器页面，然后切换到迷你模式
          Navigator.of(context).pop();
          MiniPlayerWindowService().enterMiniMode();
        },
      ),
    );
  }
}
