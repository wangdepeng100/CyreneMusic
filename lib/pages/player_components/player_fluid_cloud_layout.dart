import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/netease_artist_service.dart';
import '../../utils/theme_manager.dart';
import '../../models/lyric_line.dart';
import '../../models/track.dart';
import '../../models/song_detail.dart';
import '../../widgets/search_widget.dart';
import '../artist_detail_page.dart';
import 'player_fluid_cloud_background.dart';
import 'player_window_controls.dart';
import 'player_fluid_cloud_lyrics_panel.dart';
import 'player_dialogs.dart';

/// 流体云全屏布局
/// 模仿 Apple Music 的左右分栏设计
/// 左侧：封面、信息、控制
/// 右侧：沉浸式歌词
class PlayerFluidCloudLayout extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final bool isMaximized;
  final VoidCallback onBackPressed;
  final VoidCallback onPlaylistPressed;
  final VoidCallback onVolumeControlPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onTranslationToggle;

  const PlayerFluidCloudLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.isMaximized,
    required this.onBackPressed,
    required this.onPlaylistPressed,
    required this.onVolumeControlPressed,
    this.onSleepTimerPressed,
    this.onTranslationToggle,
  });

  @override
  State<PlayerFluidCloudLayout> createState() => _PlayerFluidCloudLayoutState();
}

class _PlayerFluidCloudLayoutState extends State<PlayerFluidCloudLayout>
    with SingleTickerProviderStateMixin {
  // 缓存当前歌曲的封面 URL，用于检测歌曲变化
  String? _currentImageUrl;

  Future<void>? _pendingCoverPrecache;
  
  // 歌词折叠状态
  bool _isLyricsCollapsed = false;
  
  // 折叠按钮显示状态（鼠标悬停时显示）
  bool _showCollapseButton = false;
  
  // 折叠动画控制器
  AnimationController? _collapseController;
  Animation<double>? _collapseAnimation;
  
  // 获取动画值，未初始化时返回 0
  double get _collapseAnimationValue => _collapseAnimation?.value ?? 0.0;
  
  @override
  void initState() {
    super.initState();
    
    // 先初始化折叠动画控制器（在其他操作之前）
    _collapseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _collapseAnimation = CurvedAnimation(
      parent: _collapseController!,
      curve: Curves.easeInOutCubic,
    );
    
    PlayerService().addListener(_onPlayerChanged);
    _updateCurrentImageUrl();
  }
  
  @override
  void dispose() {
    _collapseController?.dispose();
    PlayerService().removeListener(_onPlayerChanged);
    super.dispose();
  }
  
  /// 切换歌词折叠状态
  void _toggleLyricsCollapse() {
    setState(() {
      _isLyricsCollapsed = !_isLyricsCollapsed;
    });
    if (_isLyricsCollapsed) {
      _collapseController?.forward();
    } else {
      _collapseController?.reverse();
    }
  }
  
  void _onPlayerChanged() {
    // 检查封面 URL 是否变化
    final player = PlayerService();
    final newImageUrl = player.currentSong?.pic ?? player.currentTrack?.picUrl ?? '';
    
    if (_currentImageUrl != newImageUrl) {
      setState(() {
        _currentImageUrl = newImageUrl;
      });

      if (newImageUrl.isNotEmpty) {
        // 判断是网络 URL 还是本地文件路径
        final isNetwork = newImageUrl.startsWith('http://') || newImageUrl.startsWith('https://');
        final ImageProvider provider;
        if (isNetwork) {
          provider = CachedNetworkImageProvider(newImageUrl);
        } else {
          provider = FileImage(File(newImageUrl));
        }
        _pendingCoverPrecache = precacheImage(
          provider,
          context,
          size: const Size(512, 512),
        );
      }
    }
  }
  
  void _updateCurrentImageUrl() {
    final player = PlayerService();
    _currentImageUrl = player.currentSong?.pic ?? player.currentTrack?.picUrl ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. 全局背景（流体云专用背景：自适应模式下始终显示专辑封面 100% 填充）
        const PlayerFluidCloudBackground(),
        
        // 2. 玻璃拟态遮罩 (整个容器)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              color: Colors.black.withOpacity(0.2), // 降低亮度以突出内容
            ),
          ),
        ),

        // 3. 主要内容区域
        SafeArea(
          child: Column(
            children: [
              // 顶部窗口控制
              Builder(
                builder: (context) {
                  final player = PlayerService();
                  return PlayerWindowControls(
                    isMaximized: widget.isMaximized,
                    onBackPressed: widget.onBackPressed,
                    onPlaylistPressed: widget.onPlaylistPressed,
                    onSleepTimerPressed: widget.onSleepTimerPressed,
                    // 译文按钮相关
                    showTranslationButton: _shouldShowTranslationButton(),
                    showTranslation: widget.showTranslation,
                    onTranslationToggle: widget.onTranslationToggle,
                    // 下载按钮相关
                    currentTrack: player.currentTrack,
                    currentSong: player.currentSong,
                  );
                },
              ),
              
              // 主体布局 - 支持歌词折叠
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 60, right: 40, top: 20, bottom: 20),
                      child: AnimatedBuilder(
                        animation: _collapseController ?? const AlwaysStoppedAnimation(0.0),
                        builder: (context, child) {
                          // 计算动态布局比例
                          // 展开时: 左侧 42%, 右侧 58%
                          // 折叠时: 左侧占据全部空间居中
                          final animValue = _collapseAnimationValue;
                          final leftFlex = (42 + (58 * animValue)).round();
                          final rightFlex = (58 * (1 - animValue)).round();
                          final rightOpacity = 1.0 - animValue;
                          
                          return Stack(
                            children: [
                              // 主要内容 Row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // 左侧：控制面板 (动态宽度)
                                  Expanded(
                                    flex: leftFlex,
                                    child: Padding(
                                      // 折叠时减少右侧 padding
                                      padding: EdgeInsets.only(
                                        right: 60 * (1 - animValue) + 20 * animValue,
                                      ),
                                      child: _buildLeftPanel(context),
                                    ),
                                  ),
                                  
                                  // 折叠按钮占位（实际按钮在 Stack 中）
                                  const SizedBox(width: 48),
                                  
                                  // 右侧：歌词面板 (动态宽度，折叠时隐藏)
                                  if (rightFlex > 0)
                                    Expanded(
                                      flex: rightFlex,
                                      child: MouseRegion(
                                        onEnter: (_) => setState(() => _showCollapseButton = true),
                                        onExit: (_) => setState(() => _showCollapseButton = false),
                                        child: Opacity(
                                          opacity: rightOpacity,
                                          child: Padding(
                                            padding: const EdgeInsets.only(left: 40),
                                            child: _buildRightPanel(),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              
                              // 折叠按钮（浮动在 Stack 中）
                              // 未折叠时：在歌词区域左侧
                              // 折叠时：在窗口右侧
                              Positioned(
                                right: _isLyricsCollapsed 
                                    ? 0  // 折叠时靠右
                                    : constraints.maxWidth * 0.58 - 16, // 未折叠时在歌词区域左边
                                top: 0,
                                bottom: 0,
                                child: _isLyricsCollapsed
                                    // 折叠时：右侧热区
                                    ? MouseRegion(
                                        onEnter: (_) => setState(() => _showCollapseButton = true),
                                        onExit: (_) => setState(() => _showCollapseButton = false),
                                        child: SizedBox(
                                          width: 60,
                                          child: Center(
                                            child: _buildCollapseButton(),
                                          ),
                                        ),
                                      )
                                    // 未折叠时：按钮直接显示（由歌词区域的 MouseRegion 控制）
                                    : Center(
                                        child: _buildCollapseButton(),
                                      ),
                              ),
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建折叠按钮
  Widget _buildCollapseButton() {
    return MouseRegion(
      // 鼠标在按钮上时也保持显示
      onEnter: (_) => setState(() => _showCollapseButton = true),
      onExit: (_) => setState(() => _showCollapseButton = false),
      child: AnimatedOpacity(
        opacity: _showCollapseButton ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: GestureDetector(
          onTap: _showCollapseButton ? _toggleLyricsCollapse : null,
          child: Container(
            width: 32,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Center(
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 300),
                turns: _isLyricsCollapsed ? 0.5 : 0,
                child: Icon(
                  CupertinoIcons.chevron_right,
                  color: Colors.white.withOpacity(0.8),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建左侧面板
  Widget _buildLeftPanel(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    final imageUrl = song?.pic ?? track?.picUrl ?? '';
    
    // 获取折叠动画值
    final animValue = _collapseAnimationValue;
    // 是否处于折叠状态（动画进行中或已折叠）
    final isCollapsing = animValue > 0;

    // 构建封面 widget
    Widget cover = AspectRatio(
      aspectRatio: 1.0,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: imageUrl.isNotEmpty
            ? RepaintBoundary(
                child: _buildCoverImage(imageUrl),
              )
            : Container(
                color: Colors.grey[900],
                child: const Icon(
                  Icons.music_note,
                  size: 80,
                  color: Colors.white54,
                ),
              ),
      ),
    );

    // 根据折叠状态决定布局
    // 未折叠时：使用原有的 90% 缩放布局
    // 折叠时：居中显示，限制最大宽度
    if (isCollapsing) {
      return Center(
        child: Transform.scale(
          scale: 0.9,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 封面
                cover,
                const SizedBox(height: 40),
                
                // 歌曲信息
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        track?.name ?? '未知歌曲',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.5,
                          fontFamily: 'Microsoft YaHei',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (track != null) ...[
                      const SizedBox(width: 8),
                      _FavoriteButton(track: track),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                _buildArtistsRow(context, track?.artists ?? '未知歌手', player.currentSong),
                
                const SizedBox(height: 30),
                
                // 进度条
                AnimatedBuilder(
                  animation: player,
                  builder: (context, _) {
                    final position = player.position.inMilliseconds.toDouble();
                    final duration = player.duration.inMilliseconds.toDouble();
                    final value = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;
                    
                    return Column(
                      children: [
                        SizedBox(
                          height: 24,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 4,
                              thumbShape: const _VerticalLineThumbShape(
                                width: 4,
                                height: 24,
                                color: Colors.white,
                              ),
                              trackShape: const _GapSliderTrackShape(gap: 8.0),
                              overlayShape: SliderComponentShape.noOverlay,
                              activeTrackColor: Colors.white.withOpacity(0.9),
                              inactiveTrackColor: Colors.white.withOpacity(0.2),
                            ),
                            child: Slider(
                              value: value,
                              onChanged: (v) {
                                final pos = Duration(milliseconds: (v * duration).round());
                                player.seek(pos);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(player.position),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                            Text(
                              _formatDuration(player.duration),
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Consolas',
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 16),
                
                // 控制按钮
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.backward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasPrevious ? player.playPrevious : null,
                    ),
                    const SizedBox(width: 24),
                    AnimatedBuilder(
                      animation: player,
                      builder: (context, _) {
                        return IconButton(
                          icon: Icon(
                            player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                            color: Colors.white,
                          ),
                          iconSize: 56,
                          padding: EdgeInsets.zero,
                          onPressed: player.togglePlayPause,
                        );
                      },
                    ),
                    const SizedBox(width: 24),
                    IconButton(
                      icon: const Icon(CupertinoIcons.forward_fill),
                      color: Colors.white.withOpacity(0.9),
                      iconSize: 36,
                      onPressed: player.hasNext ? player.playNext : null,
                    ),
                  ],
                ),
                
                const SizedBox(height: 20),
                
                // 音量控制
                _buildVolumeSlider(player),
              ],
            ),
          ),
        ),
      );
    }
    
    // 未折叠时：原有布局
    return Transform.scale(
      scale: 0.9,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. 专辑封面
          cover,
          
          const SizedBox(height: 40),
          
          // 2. 歌曲信息（歌曲名 + 收藏按钮）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  track?.name ?? '未知歌曲',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (track != null) ...[
                const SizedBox(width: 8),
                _FavoriteButton(track: track),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 歌手名（可点击）
          _buildArtistsRow(context, track?.artists ?? '未知歌手', player.currentSong),
          
          const SizedBox(height: 30),
          
          // 3. 进度条 - MD3 风格 (竖线滑块 + 分离式轨道，与移动端一致)
          AnimatedBuilder(
            animation: player,
            builder: (context, _) {
              final position = player.position.inMilliseconds.toDouble();
              final duration = player.duration.inMilliseconds.toDouble();
              final value = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;
              
              return Column(
                children: [
                  // 进度条 - MD3 风格 (竖线滑块 + 分离式轨道)
                  SizedBox(
                    height: 24, // 增加点击热区
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const _VerticalLineThumbShape(
                          width: 4,
                          height: 24,
                          color: Colors.white,
                        ),
                        trackShape: const _GapSliderTrackShape(gap: 8.0),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: Colors.white.withOpacity(0.9),
                        inactiveTrackColor: Colors.white.withOpacity(0.2),
                      ),
                      child: Slider(
                        value: value,
                        onChanged: (v) {
                          final pos = Duration(milliseconds: (v * duration).round());
                          player.seek(pos);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(player.position),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6), 
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Consolas',
                          ),
                        ),
                        Text(
                          _formatDuration(player.duration),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6), 
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
          ),
          
          const SizedBox(height: 16),
          
          // 4. 控制按钮 (居中，作为一个整体) - iOS/Cupertino 风格图标，与移动端一致
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 上一首 - iOS 风格粗图标
                IconButton(
                  icon: const Icon(CupertinoIcons.backward_fill),
                  color: Colors.white.withOpacity(0.9),
                  iconSize: 36,
                  onPressed: player.hasPrevious ? player.playPrevious : null,
                ),
                const SizedBox(width: 24),
                
                // 播放/暂停 - iOS 风格粗图标
                AnimatedBuilder(
                  animation: player,
                  builder: (context, _) {
                    return IconButton(
                      icon: Icon(
                        player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                        color: Colors.white,
                      ),
                      iconSize: 56,
                      padding: EdgeInsets.zero,
                      onPressed: player.togglePlayPause,
                    );
                  }
                ),
                const SizedBox(width: 24),
                
                // 下一首 - iOS 风格粗图标
                IconButton(
                  icon: const Icon(CupertinoIcons.forward_fill),
                  color: Colors.white.withOpacity(0.9),
                  iconSize: 36,
                  onPressed: player.hasNext ? player.playNext : null,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // 5. 音量控制 (与进度条样式一致)
          _buildVolumeSlider(player),
          
        ],
      ),
    );
  }
  
  /// 构建音量滑条 - MD3 风格 (竖线滑块 + 分离式轨道，与移动端一致)
  Widget _buildVolumeSlider(PlayerService player) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Row(
          children: [
            // 静音图标
            Icon(
              CupertinoIcons.speaker_fill,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
            const SizedBox(width: 8),
            
            // 音量滑条 - MD3 风格 (竖线滑块 + 分离式轨道)
            Expanded(
              child: SizedBox(
                height: 20,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const _VerticalLineThumbShape(
                      width: 4,
                      height: 20,
                      color: Colors.white,
                    ),
                    trackShape: const _GapSliderTrackShape(gap: 8.0),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: Colors.white.withOpacity(0.9),
                    inactiveTrackColor: Colors.white.withOpacity(0.2),
                  ),
                  child: Slider(
                    value: player.volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      player.setVolume(v);
                    },
                  ),
                ),
              ),
            ),
            
            const SizedBox(width: 8),
            // 最大音量图标
            Icon(
              CupertinoIcons.speaker_3_fill,
              color: Colors.white.withOpacity(0.5),
              size: 16,
            ),
          ],
        );
      },
    );
  }

  /// 构建右侧面板 (歌词)
  Widget _buildRightPanel() {
    // 使用 ShaderMask 实现上下淡入淡出
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, 0.15, 0.85, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: PlayerFluidCloudLyricsPanel(
        lyrics: widget.lyrics,
        currentLyricIndex: widget.currentLyricIndex,
        showTranslation: widget.showTranslation,
      ),
    );
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  Widget _buildCoverImage(String imageUrl) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    
    if (isNetwork) {
      return CachedNetworkImage(
        key: ValueKey(imageUrl),
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        memCacheWidth: 1024,
        memCacheHeight: 1024,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => Container(
          color: Colors.grey[900],
        ),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
        ),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        key: ValueKey(imageUrl),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
          child: const Icon(
            Icons.music_note,
            size: 80,
            color: Colors.white54,
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 判断是否应该显示译文按钮
  /// 只有当歌词非中文且存在翻译时才显示
  bool _shouldShowTranslationButton() {
    if (widget.lyrics.isEmpty) return false;
    
    // 检查是否有翻译
    final hasTranslation = widget.lyrics.any((lyric) => 
      lyric.translation != null && lyric.translation!.isNotEmpty
    );
    
    if (!hasTranslation) return false;
    
    // 检查原文是否为中文（检查前几行非空歌词）
    final sampleLyrics = widget.lyrics
        .where((lyric) => lyric.text.trim().isNotEmpty)
        .take(5)
        .map((lyric) => lyric.text)
        .join('');
    
    if (sampleLyrics.isEmpty) return false;
    
    // 判断是否主要为中文（中文字符占比）
    final chineseCount = sampleLyrics.runes.where((rune) {
      return (rune >= 0x4E00 && rune <= 0x9FFF) || // 基本汉字
             (rune >= 0x3400 && rune <= 0x4DBF) || // 扩展A
             (rune >= 0x20000 && rune <= 0x2A6DF); // 扩展B
    }).length;
    
    final totalCount = sampleLyrics.runes.length;
    final chineseRatio = totalCount > 0 ? chineseCount / totalCount : 0;
    
    // 如果中文字符占比小于30%，认为是非中文歌词
    return chineseRatio < 0.3;
  }

  /// 构建歌手行（支持多歌手点击）
  Widget _buildArtistsRow(BuildContext context, String artistsStr, SongDetail? song) {
    final artists = _splitArtists(artistsStr);
    
    return Wrap(
      alignment: WrapAlignment.center,
      children: artists.asMap().entries.map((entry) {
        final index = entry.key;
        final artist = entry.value;
        
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _onArtistTap(context, artist, song),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  artist,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withOpacity(0.6),
                    fontFamily: 'Microsoft YaHei',
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            ),
            if (index < artists.length - 1)
              Text(
                ' / ',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.6),
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
          ],
        );
      }).toList(),
    );
  }

  /// 分割歌手字符串（支持多种分隔符）
  List<String> _splitArtists(String artistsStr) {
    final separators = ['/', ',', '、'];
    
    for (final separator in separators) {
      if (artistsStr.contains(separator)) {
        return artistsStr
            .split(separator)
            .map((a) => a.trim())
            .where((a) => a.isNotEmpty)
            .toList();
      }
    }
    
    return [artistsStr];
  }

  /// 歌手点击处理
  Future<void> _onArtistTap(BuildContext context, String artistName, SongDetail? song) async {
    // 仅在网易云音乐来源时跳转歌手详情，否则沿用搜索
    if (song?.source != MusicSource.netease) {
      _searchInDialog(context, artistName);
      return;
    }
    // 解析歌手ID（后端无返回ID时，通过搜索解析）
    final id = await NeteaseArtistDetailService().resolveArtistIdByName(artistName);
    if (id == null) {
      _searchInDialog(context, artistName);
      return;
    }
    if (!context.mounted) return;
    
    final isFluent = ThemeManager().isFluentFramework;
    
    if (isFluent) {
      // Fluent UI 样式对话框
      final fluentTheme = fluent.FluentTheme.of(context);
      final backgroundColor = fluentTheme.micaBackgroundColor ?? 
          fluentTheme.scaffoldBackgroundColor;
      
      fluent.showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => fluent.ContentDialog(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          style: fluent.ContentDialogThemeData(
            padding: EdgeInsets.zero,
            bodyPadding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: fluentTheme.resources.surfaceStrokeColorDefault,
                width: 1,
              ),
            ),
          ),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 800,
              height: 700,
              child: ArtistDetailContent(artistId: id),
            ),
          ),
        ),
      );
    } else {
      // Material 样式对话框
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ArtistDetailContent(artistId: id),
            ),
          ),
        ),
      );
    }
  }

  /// 在对话框中打开搜索
  void _searchInDialog(BuildContext context, String keyword) {
    final isFluent = ThemeManager().isFluentFramework;
    
    if (isFluent) {
      // Fluent UI 样式对话框
      final fluentTheme = fluent.FluentTheme.of(context);
      final backgroundColor = fluentTheme.micaBackgroundColor ?? 
          fluentTheme.scaffoldBackgroundColor;
      
      fluent.showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => fluent.ContentDialog(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          style: fluent.ContentDialogThemeData(
            padding: EdgeInsets.zero,
            bodyPadding: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: fluentTheme.resources.surfaceStrokeColorDefault,
                width: 1,
              ),
            ),
          ),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 800,
              height: 700,
              child: SearchWidget(
                onClose: () => Navigator.pop(context),
                initialKeyword: keyword,
              ),
            ),
          ),
        ),
      );
    } else {
      // Material 样式对话框
      showDialog(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 800,
              maxHeight: 700,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: SearchWidget(
                onClose: () => Navigator.pop(context),
                initialKeyword: keyword,
              ),
            ),
          ),
        ),
      );
    }
  }
}

/// 收藏按钮组件
/// 检测歌曲是否在用户歌单中，显示实心或空心爱心
class _FavoriteButton extends StatefulWidget {
  final Track track;

  const _FavoriteButton({required this.track});

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  bool _isInPlaylist = false;
  bool _isLoading = true;
  List<String> _playlistNames = [];

  @override
  void initState() {
    super.initState();
    _checkIfInPlaylist();
  }

  @override
  void didUpdateWidget(_FavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当歌曲变化时重新检查
    if (oldWidget.track.id != widget.track.id || 
        oldWidget.track.source != widget.track.source) {
      _checkIfInPlaylist();
    }
  }

  Future<void> _checkIfInPlaylist() async {
    setState(() => _isLoading = true);
    
    final playlistService = PlaylistService();
    
    // 调用后端 API 检查歌曲是否在任何歌单中
    final result = await playlistService.isTrackInAnyPlaylist(widget.track);
    
    if (mounted) {
      setState(() {
        _isInPlaylist = result.inPlaylist;
        _playlistNames = result.playlistNames;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    final tooltip = _isInPlaylist 
        ? '已收藏到: ${_playlistNames.join(", ")}' 
        : '添加到歌单';

    return IconButton(
      icon: Icon(
        _isInPlaylist ? Icons.favorite : Icons.favorite_border,
        color: _isInPlaylist ? Colors.redAccent : Colors.white.withOpacity(0.7),
        size: 26,
      ),
      onPressed: () {
        PlayerDialogs.showAddToPlaylist(context, widget.track);
      },
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 32,
        minHeight: 32,
      ),
    );
  }
}

/// 自定义竖线滑块形状 (Material Design 3 风格)
class _VerticalLineThumbShape extends SliderComponentShape {
  final double width;
  final double height;
  final Color color;
  final double radius;

  const _VerticalLineThumbShape({
    this.width = 4.0, // MD3 Spec: 4dp
    this.height = 44.0, // MD3 Spec: 44dp (Active handle height)
    this.color = Colors.white,
    this.radius = 2.0, // MD3 Spec: 2dp
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return Size(width, height);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;

    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    // 绘制圆角矩形竖线
    final RRect rRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: width,
        height: height * activationAnimation.value.clamp(0.5, 1.0), // 动画效果
      ),
      Radius.circular(radius),
    );

    canvas.drawRRect(rRect, paint);
  }
}

/// 自定义带有间隙的轨道形状，确保滑块左右两侧不与轨道相连
class _GapSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  final double gap; // 滑块中心到轨道的间隔

  const _GapSliderTrackShape({this.gap = 6.0});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    // 获取颜色
    final ColorTween activeTrackColorTween = ColorTween(
        begin: sliderTheme.disabledActiveTrackColor,
        end: sliderTheme.activeTrackColor);
    final ColorTween inactiveTrackColorTween = ColorTween(
        begin: sliderTheme.disabledInactiveTrackColor,
        end: sliderTheme.inactiveTrackColor);
    final Paint activePaint = Paint()
      ..color = activeTrackColorTween.evaluate(enableAnimation)!;
    final Paint inactivePaint = Paint()
      ..color = inactiveTrackColorTween.evaluate(enableAnimation)!;

    // 获取轨道矩形
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackHeight = sliderTheme.trackHeight!;
    final double trackCenterY = offset.dy + (parentBox.size.height) / 2;
    final Radius trackRadius = Radius.circular(trackHeight / 2);

    // 计算 Active Track (左侧)
    // 从轨道左端到滑块中心减去间隙
    final double activeRight = thumbCenter.dx - gap;
    final double activeLeft = trackRect.left;

    if (activeRight > activeLeft) {
      final Rect activeRect = Rect.fromLTRB(
        activeLeft,
        trackCenterY - trackHeight / 2,
        activeRight,
        trackCenterY + trackHeight / 2,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(activeRect, trackRadius),
        activePaint,
      );
    }

    // 计算 Inactive Track (右侧)
    // 从滑块中心加上间隙到轨道右端
    final double inactiveLeft = thumbCenter.dx + gap;
    final double inactiveRight = trackRect.right;

    if (inactiveRight > inactiveLeft) {
      final Rect inactiveRect = Rect.fromLTRB(
        inactiveLeft,
        trackCenterY - trackHeight / 2,
        inactiveRight,
        trackCenterY + trackHeight / 2,
      );
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(inactiveRect, trackRadius),
        inactivePaint,
      );
    }
  }
}

