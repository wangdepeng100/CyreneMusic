import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/playlist_service.dart';
import '../../services/download_service.dart';
import '../../services/music_service.dart';
import '../../models/lyric_line.dart';
import '../../models/track.dart';
import '../player_components/player_fluid_cloud_lyrics_panel.dart';
import 'mobile_player_dialogs.dart';
import 'mobile_player_settings_sheet.dart';
import 'dart:async';
import '../../services/auto_collapse_service.dart';

/// 移动端流体云播放器布局
/// 参考 HTML 设计：统一在同一页面显示歌曲信息、歌词、控制按钮
/// 歌词样式参考桌面端流体云歌词，显示3行
class MobilePlayerFluidCloudLayout extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlaylistPressed;
  final VoidCallback? onTranslationToggle;

  const MobilePlayerFluidCloudLayout({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
    required this.onBackPressed,
    this.onPlaylistPressed,
    this.onTranslationToggle,
  });

  @override
  State<MobilePlayerFluidCloudLayout> createState() => _MobilePlayerFluidCloudLayoutState();
}

class _MobilePlayerFluidCloudLayoutState extends State<MobilePlayerFluidCloudLayout> {
  // 自动折叠逻辑
  bool _isControlsVisible = true;
  Timer? _collapseTimer;
  bool _wasPlaying = false;
  // 封面模式 (经典模式)
  bool _showCoverMode = false;

  
  @override
  void initState() {
    super.initState();
    _wasPlaying = PlayerService().isPlaying;
    // 监听播放状态变化以控制计时器
    PlayerService().addListener(_onPlayerStateChanged);
    // 监听设置变化
    AutoCollapseService().addListener(_onSettingsChanged);
    
    // 初始化时如果正在播放且开启了折叠，启动计时器
    if (_wasPlaying && AutoCollapseService().isAutoCollapseEnabled) {
      _resetCollapseTimer();
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    PlayerService().removeListener(_onPlayerStateChanged);
    AutoCollapseService().removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    // 如果设置关闭，确保控件显示
    if (!AutoCollapseService().isAutoCollapseEnabled) {
      _showControls(autoHide: false);
    } else {
      // 开启时，如果正在播放，重置计时器
      if (PlayerService().isPlaying && _isControlsVisible) {
        _resetCollapseTimer();
      }
    }
  }

  void _onPlayerStateChanged() {
    // 仅在播放状态改变时处理
    final isPlaying = PlayerService().isPlaying;
    if (isPlaying != _wasPlaying) {
      _wasPlaying = isPlaying;
      
      if (AutoCollapseService().isAutoCollapseEnabled) {
        if (isPlaying) {
          // 开始播放，如果控件可见，启动计时器
          if (_isControlsVisible) {
            _resetCollapseTimer();
          }
        } else {
          // 暂停时始终显示
          _showControls(autoHide: false);
        }
      }
    }
  }

  /// 显示控制栏
  /// [autoHide] 是否在显示后自动启动隐藏倒计时
  void _showControls({bool autoHide = true}) {
    if (!_isControlsVisible) {
      setState(() => _isControlsVisible = true);
    }
    
    if (autoHide && AutoCollapseService().isAutoCollapseEnabled && PlayerService().isPlaying) {
      _resetCollapseTimer();
    } else {
      _collapseTimer?.cancel();
    }
  }

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    if (AutoCollapseService().isAutoCollapseEnabled && PlayerService().isPlaying) {
      _collapseTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() => _isControlsVisible = false);
        }
      });
    }
  }

  /// 切换控制栏可见性
  void _toggleControls() {
    if (AutoCollapseService().isAutoCollapseEnabled) {
      if (_isControlsVisible) {
        // 如果当前可见，手动点击则隐藏（可选，或只是忽略）
        setState(() => _isControlsVisible = false);
      } else {
        // 如果当前隐藏，点击则显示
        _showControls();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerService();
    final song = player.currentSong;
    final track = player.currentTrack;
    final imageUrl = song?.pic ?? track?.picUrl ?? '';

    // 检测屏幕方向
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;

    // 不再创建自己的背景，背景由 MobilePlayerBackground 统一处理
    // 这里只负责内容布局
    if (isLandscape) {
      // 横屏模式：左右分栏布局
      return _buildLandscapeLayout(context, player, song, track, imageUrl);
    }

    // 竖屏模式：使用 Stack + AnimatedPositioned 实现丝滑切换
    
    // 计算布局参数
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final safePadding = MediaQuery.of(context).padding;
    
    // --- 封面模式参数计算 ---
    // 预留底部高度 (标题+歌词+进度条+控制栏+底部导航+间距)
    const reservedBottomHeight = 350.0;
    
    final topBarHeight = 50.0;
    // 封面起始 Y 坐标 (绝对坐标)
    // 保证在 TopBar 下方，且距离顶部有一定比例
    final minCoverTop = safePadding.top + topBarHeight + 20;
    final idealCoverTop = screenHeight * 0.15;
    final bigCoverTop = idealCoverTop < minCoverTop ? minCoverTop : idealCoverTop;
    
    // 计算可用高度
    final availableHeight = screenHeight - bigCoverTop - reservedBottomHeight;
    // 封面尺寸：宽度限制(屏幕-64)，高度限制(可用高度)
    final bigCoverSize = (screenWidth - 64).clamp(100.0, availableHeight < 100 ? 100.0 : availableHeight);
    
    // 水平居中
    final bigCoverLeft = (screenWidth - bigCoverSize) / 2;

    // --- 歌词模式参数 ---
    final smallCoverSize = 56.0;
    final smallCoverTop = safePadding.top + 8.0;
    final smallCoverLeft = 16.0;

    return Stack(
      children: [
        // 1. 歌词模式布局 (底层)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showCoverMode ? 0.0 : 1.0,
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: _showCoverMode,
            child: GestureDetector(
              onTap: _toggleControls, // 支持点击空白收起控制栏
              behavior: HitTestBehavior.translucent,
              child: Column(
                children: [
                  // 顶部歌曲信息 (isGhost=true, 封面占位)
                  _buildSongInfoSection(context, song, track, imageUrl, isGhost: true),
            
                  // 中间歌词区域
                  Expanded(
                    child: _buildLyricsSection(),
                  ),
            
                  // 底部控制
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: _isControlsVisible ? 1.0 : 0.0,
                      child: _isControlsVisible
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: const Offset(0, -24),
                                  child: _buildControlsSection(player),
                                ),
                                _buildBottomNavigation(context, track),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  
                  if (!_isControlsVisible)
                     const SizedBox(height: 16),
                  
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),

        // 2. 封面模式布局 (中层)
        AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _showCoverMode ? 1.0 : 0.0,
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !_showCoverMode,
            child: _buildCoverModeLayout(
              context, 
              player, 
              song, 
              track, 
              imageUrl, 
              coverSize: bigCoverSize,
              topSpacing: bigCoverTop - safePadding.top - topBarHeight, // 传递准确的间距
              isGhost: true,
            ),
          ),
        ),

        // 3. 浮动封面 (顶层，负责动画)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 500),
          curve: Curves.fastLinearToSlowEaseIn,
          top: _showCoverMode ? bigCoverTop : smallCoverTop,
          left: _showCoverMode ? bigCoverLeft : smallCoverLeft,
          width: _showCoverMode ? bigCoverSize : smallCoverSize,
          height: _showCoverMode ? bigCoverSize : smallCoverSize,
          child: GestureDetector(
            onTap: () {
              // 点击切换模式
              setState(() => _showCoverMode = !_showCoverMode);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.fastLinearToSlowEaseIn,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_showCoverMode ? 16 : 8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(_showCoverMode ? 0.4 : 0.3),
                    blurRadius: _showCoverMode ? 40 : 10,
                    offset: Offset(0, _showCoverMode ? 20 : 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl.isNotEmpty
                  ? _buildCoverImage(imageUrl)
                  : Container(
                      color: Colors.grey[900],
                      child: Icon(
                        Icons.music_note, 
                        color: Colors.white54,
                        size: _showCoverMode ? 120 : 30,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// 构建封面模式布局 (大封面 + 控制器，无歌词)
  Widget _buildCoverModeLayout(
    BuildContext context,
    PlayerService player,
    dynamic song,
    dynamic track,
    String imageUrl, {
    required double coverSize,
    required double topSpacing,
    bool isGhost = false,
  }) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artists = song?.arName ?? track?.artists ?? '未知艺术家';
    
    return SafeArea(
      key: const ValueKey('CoverModeLayout'),
      child: Column(
        children: [
          // 顶部栏
          SizedBox(
            height: 50, // 与 topBarHeight 一致
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end, 
                children: [
                   IconButton(
                    icon: Icon(
                      Icons.more_horiz,
                      color: Colors.white.withOpacity(0.8),
                    ),
                    onPressed: () {
                      MobilePlayerSettingsSheet.show(context, currentTrack: track);
                    },
                  ),
                ],
              ),
            ),
          ),
          
          // 精确控制封面位置，使其与 AnimatedPositioned 重合
          SizedBox(height: topSpacing > 0 ? topSpacing : 0),
          
          // 大封面占位
          GestureDetector(
            onTap: () {
               if (!isGhost) setState(() => _showCoverMode = false);
            },
            child: Container(
              width: coverSize,
              height: coverSize,
              color: Colors.transparent, 
            ),
          ),
          
          // 剩余空间分配给文本和控件
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end, // 靠底对齐
              children: [
                const Spacer(), // 弹性空间，确保内容不要贴着封面
                
                // 歌曲信息
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              artists,
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withOpacity(0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                       if (track != null) _FavoriteButton(track: track),
                    ],
                  ),
                ),
                
                // 控制区
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildControlsSection(player), 
                ),
                
                // 底部导航
                _buildBottomNavigation(context, track),
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
  

  /// 横屏模式布局 - 参考图片设计
  /// 左侧：专辑封面 + 进度条 (统一水平线)
  /// 右侧：歌曲信息 + 歌词 + 控制按钮 (统一水平线)
  Widget _buildLandscapeLayout(
    BuildContext context,
    PlayerService player,
    dynamic song,
    dynamic track,
    String imageUrl,
  ) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artist = song?.arName ?? track?.artists ?? '未知艺术家';
    
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom; // 底部安全区
    
    // 封面大小
    final coverSize = (screenHeight - safeAreaBottom - 60) * 0.65;
    final progressBarWidth = coverSize + 48; // 进度条比封面略宽

    // 底部对齐的高度 (控制栏高度)
    const bottomControlsHeight = 60.0;
    // 底部留白
    const bottomPadding = 24.0; 

    return SafeArea(
      child: Stack(
        children: [
          // 右上角更多按钮
          Positioned(
            top: 8,
            right: 16,
            child: IconButton(
              icon: Icon(
                Icons.more_horiz,
                color: Colors.white.withOpacity(0.8),
              ),
              iconSize: 24,
              onPressed: () {
                MobilePlayerSettingsSheet.show(context, currentTrack: track);
              },
            ),
          ),

          // 主布局
          Padding(
            padding: const EdgeInsets.only(bottom: bottomPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end, // 底部对齐，保证进度条和控制栏在同一水平线
              children: [
                // 1. 左侧面板: 封面 + 进度条
                Expanded(
                  flex: 4, 
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end, // 底部对齐
                    children: [
                      const Spacer(),
                      // 封面
                       Container(
                        width: coverSize,
                        height: coverSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.4),
                              blurRadius: 24,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imageUrl.isNotEmpty
                            ? _buildCoverImage(imageUrl)
                            : Container(
                                color: Colors.grey[900],
                                child: const Icon(
                                  Icons.music_note,
                                  size: 80,
                                  color: Colors.white54,
                                ),
                              ),
                      ),
                      
                      const Spacer(), // 封面和进度条之间的弹簧

                      // 底部进度条 (高度与右侧控制栏对齐容器)
                      SizedBox(
                        height: bottomControlsHeight,
                        child: Center(
                          child: _buildLandscapeProgressBar(player, progressBarWidth),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. 右侧面板: 信息 + 歌词 + 控制按钮
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 24, 32, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部信息
                        _buildLandscapeTitleSection(name, artist),
                        const SizedBox(height: 16),
                        
                        // 歌词
                        Expanded(
                          child: _buildLandscapeLyricsSection(),
                        ),
                        
                        const SizedBox(height: 12),

                        // 底部控制必须有固定高度，以便与左侧对齐
                        SizedBox(
                          height: bottomControlsHeight,
                          child: _buildLandscapeBottomControls(context, player, track),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 横屏标题区域
  Widget _buildLandscapeTitleSection(String name, String artist) {
    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
                const TextSpan(text: '  '),
                TextSpan(
                  text: artist,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'Microsoft YaHei',
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  /// 横屏进度条 (用于左侧)
  Widget _buildLandscapeProgressBar(PlayerService player, double width) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final position = player.position.inMilliseconds.toDouble();
        final duration = player.duration.inMilliseconds.toDouble();
        final progress = (duration > 0) ? (position / duration).clamp(0.0, 1.0) : 0.0;

        return SizedBox(
          width: width,
          height: 20, // 点击热区
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4, 
              thumbShape: const _VerticalLineThumbShape(
                width: 4, 
                height: 20, 
                color: Colors.white,
              ),
              trackShape: const _GapSliderTrackShape(gap: 8.0), // 增加间隙：滑块宽4，半宽2，加6px间距 = 8
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: Colors.white.withOpacity(0.9),
              inactiveTrackColor: Colors.white.withOpacity(0.15),
            ),
            child: Slider(
              value: progress,
              onChanged: (v) {
                final pos = Duration(milliseconds: (v * duration).round());
                player.seek(pos);
              },
            ),
          ),
        );
      },
    );
  }

  /// 横屏底部控制区 (仅控制按钮 + 时间)
  Widget _buildLandscapeBottomControls(BuildContext context, PlayerService player, Track? track) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center, // 垂直居中
          children: [
             // 时间 - 字体加大
             Text(
               '${_formatDurationCompact(player.position)}/${_formatDurationCompact(player.duration)}',
               style: TextStyle(
                 color: Colors.white.withOpacity(0.6),
                 fontSize: 16, // 加大字体
                 fontWeight: FontWeight.bold,
                 fontFamily: 'Consolas',
                 letterSpacing: 0.5,
               ),
             ),

             // 控制按钮行 - 居中且使用 iOS 粗图标
             Expanded(
               child: Center(
                 child: Row(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     // 上一首
                     IconButton(
                       icon: const Icon(CupertinoIcons.backward_fill), // iOS 风格粗图标
                       color: Colors.white,
                       iconSize: 36, // 图标加大
                       onPressed: player.hasPrevious ? player.playPrevious : null,
                     ),
                     const SizedBox(width: 16),
                     
                     // 播放/暂停
                     IconButton(
                       icon: Icon(
                         player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                         color: Colors.white,
                       ),
                       iconSize: 56, // 加大图标尺寸，保持醒目
                       padding: EdgeInsets.zero,
                       onPressed: player.togglePlayPause,
                     ),
                     const SizedBox(width: 16),
                     
                     // 下一首
                     IconButton(
                       icon: const Icon(CupertinoIcons.forward_fill), // iOS 风格粗图标
                       color: Colors.white,
                       iconSize: 36, // 图标加大
                       onPressed: player.hasNext ? player.playNext : null,
                     ),
                   ],
                 ),
               ),
             ),
             
             // 喜欢按钮
             if (track != null) _FavoriteButton(track: track),
          ],
        );
      },
    );
  }

  /// 横屏模式歌词区域
  Widget _buildLandscapeLyricsSection() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: const [0.0, 0.08, 0.92, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: PlayerFluidCloudLyricsPanel(
        lyrics: widget.lyrics,
        currentLyricIndex: widget.currentLyricIndex,
        showTranslation: widget.showTranslation,
        visibleLineCount: 3, 
      ),
    );
  }

  /// 格式化时间（紧凑格式：00:01）
  String _formatDurationCompact(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 构建歌曲信息区域（参考 HTML section#song-info）
  Widget _buildSongInfoSection(BuildContext context, dynamic song, dynamic track, String imageUrl, {bool isGhost = false}) {
    final name = song?.name ?? track?.name ?? '未知歌曲';
    final artists = song?.arName ?? track?.artists ?? '未知艺术家';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          // 专辑封面占位 (实际封面由顶层 Stack 处理)
          GestureDetector(
            onTap: () {
               if (!isGhost) setState(() => _showCoverMode = true);
            },
            child: Container(
              width: 56,
              height: 56,
              color: Colors.transparent, // 占位透明
            ),
          ),
          const SizedBox(width: 12),

          // 歌曲标题和歌手
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  artists,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                    fontFamily: 'Microsoft YaHei',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 右侧操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 收藏按钮
              if (track != null)
                _FavoriteButton(track: track),
              // 更多选项 - 弹出设置侧边栏
              IconButton(
                icon: Icon(
                  Icons.more_vert,
                  color: Colors.white.withOpacity(0.8),
                ),
                onPressed: () {
                  MobilePlayerSettingsSheet.show(context, currentTrack: track);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建歌词区域 - 复用桌面端流体云歌词组件，通过遮罩限制只显示3行
  Widget _buildLyricsSection() {
    return ShaderMask(
      shaderCallback: (Rect bounds) {
        // 上下渐变遮罩
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.black,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: const [
            0.0,    // 顶部完全透明
            0.15,   // 开始可见
            0.5,    // 中心
            0.85,   // 依然可见
            0.95,   // 开始渐变
            1.0,    // 底部完全透明
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: PlayerFluidCloudLyricsPanel(
        lyrics: widget.lyrics,
        currentLyricIndex: widget.currentLyricIndex,
        showTranslation: widget.showTranslation,
        // 当控制栏隐藏时，显示更多行数 (例如 9 行)，否则显示 5 行 (原有逻辑似乎是3行可见，但Panel默认7)
        // 这里的可见行数决定了字体大小和行高计算
        visibleLineCount: _isControlsVisible ? 5 : 8, 
      ),
    );
  }

  /// 构建控制区域（进度条 + 播放按钮）
  Widget _buildControlsSection(PlayerService player) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(
        children: [
          // 进度条
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
                     height: 20, // 增加点击热区
                     child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 4,
                        thumbShape: const _VerticalLineThumbShape(
                          width: 4,
                          height: 20,
                          color: Colors.white,
                        ),
                        // 增加间隙
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
                  
                  const SizedBox(height: 8),

                  // 时间显示
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(player.position),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14, 
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Consolas',
                          ),
                        ),
                        Text(
                          _formatDuration(player.duration),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14, 
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // 播放控制按钮 (iOS 风格)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // 上一首
              IconButton(
                icon: const Icon(CupertinoIcons.backward_fill),
                color: Colors.white.withOpacity(0.9),
                iconSize: 42, 
                onPressed: player.hasPrevious ? player.playPrevious : null,
              ),
              
              // 播放/暂停（大图标，无圆形背景）
              AnimatedBuilder(
                animation: player,
                builder: (context, _) {
                  return IconButton(
                    icon: Icon(
                      player.isPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                      color: Colors.white,
                    ),
                    iconSize: 72, 
                    padding: EdgeInsets.zero,
                    onPressed: player.togglePlayPause,
                  );
                },
              ),
              
              // 下一首
              IconButton(
                icon: const Icon(CupertinoIcons.forward_fill),
                color: Colors.white.withOpacity(0.9),
                iconSize: 42, 
                onPressed: player.hasNext ? player.playNext : null,
              ),
            ],
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// 构建底部导航（参考 HTML footer#bottom-nav）
  Widget _buildBottomNavigation(BuildContext context, Track? track) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧：下载按钮
          if (track != null)
            _DownloadButton(track: track)
          else
            const SizedBox(width: 48),

          // 中间区域：译文按钮 + 返回按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 译文按钮（如果有译文）
              if (_shouldShowTranslationButton())
                _buildTranslationButton(),
              
              // 返回按钮
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                color: Colors.white.withOpacity(0.8),
                iconSize: 32,
                onPressed: widget.onBackPressed,
              ),
            ],
          ),

          // 右侧：播放列表按钮
          IconButton(
            icon: const Icon(Icons.queue_music_rounded),
            color: Colors.white.withOpacity(0.8),
            iconSize: 28,
            onPressed: widget.onPlaylistPressed,
          ),
        ],
      ),
    );
  }

  /// 构建译文切换按钮
  Widget _buildTranslationButton() {
    return GestureDetector(
      onTap: widget.onTranslationToggle,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: widget.showTranslation
              ? Colors.white.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ),
      ),
    );
  }

  /// 判断是否应该显示译文按钮
  bool _shouldShowTranslationButton() {
    if (widget.lyrics.isEmpty) return false;

    final hasTranslation = widget.lyrics.any((lyric) =>
        lyric.translation != null && lyric.translation!.isNotEmpty);

    if (!hasTranslation) return false;

    final sampleLyrics = widget.lyrics
        .where((lyric) => lyric.text.trim().isNotEmpty)
        .take(5)
        .map((lyric) => lyric.text)
        .join('');

    if (sampleLyrics.isEmpty) return false;

    final chineseCount = sampleLyrics.runes.where((rune) {
      return (rune >= 0x4E00 && rune <= 0x9FFF) ||
          (rune >= 0x3400 && rune <= 0x4DBF) ||
          (rune >= 0x20000 && rune <= 0x2A6DF);
    }).length;

    final totalCount = sampleLyrics.runes.length;
    final chineseRatio = totalCount > 0 ? chineseCount / totalCount : 0;

    return chineseRatio < 0.3;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 构建封面图片（支持网络 URL 和本地文件路径）
  Widget _buildCoverImage(String imageUrl) {
    // 判断是网络 URL 还是本地文件路径
    final isNetwork = imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    
    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(color: Colors.grey[900]),
        errorWidget: (context, url, error) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.music_note, color: Colors.white54),
        ),
      );
    } else {
      // 本地文件
      return Image.file(
        File(imageUrl),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
          child: const Icon(Icons.music_note, color: Colors.white54),
        ),
      );
    }
  }
}

/// 收藏按钮组件
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
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkIfInPlaylist();
    }
  }

  Future<void> _checkIfInPlaylist() async {
    setState(() => _isLoading = true);

    final playlistService = PlaylistService();
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
        width: 40,
        height: 40,
        child: Padding(
          padding: EdgeInsets.all(10.0),
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
        color: _isInPlaylist ? Colors.redAccent : Colors.white.withOpacity(0.8),
      ),
      onPressed: () {
        MobilePlayerDialogs.showAddToPlaylist(context, widget.track);
      },
      tooltip: tooltip,
    );
  }
}

/// 下载按钮组件
class _DownloadButton extends StatefulWidget {
  final Track track;

  const _DownloadButton({required this.track});

  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  bool _isLoading = true;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
    DownloadService().addListener(_onDownloadChanged);
  }

  @override
  void dispose() {
    DownloadService().removeListener(_onDownloadChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id ||
        oldWidget.track.source != widget.track.source) {
      _checkDownloadStatus();
    }
  }

  void _onDownloadChanged() {
    if (!mounted) return;
    
    final downloadService = DownloadService();
    final trackId = '${widget.track.source.name}_${widget.track.id}';
    final tasks = downloadService.downloadTasks;
    final task = tasks[trackId];
    
    if (task != null) {
      setState(() {
        _isDownloading = !task.isCompleted && !task.isFailed;
        _progress = task.progress;
        if (task.isCompleted) {
          _isDownloaded = true;
          _isDownloading = false;
        }
      });
    }
  }

  Future<void> _checkDownloadStatus() async {
    setState(() => _isLoading = true);
    
    final isDownloaded = await DownloadService().isDownloaded(widget.track);
    
    if (mounted) {
      setState(() {
        _isDownloaded = isDownloaded;
        _isLoading = false;
      });
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading || _isDownloaded) return;
    
    setState(() {
      _isDownloading = true;
      _progress = 0.0;
    });
    
    try {
      // 获取歌曲详情
      final songDetail = PlayerService().currentSong;
      if (songDetail == null) {
        // 如果当前没有歌曲详情，尝试获取
        final detail = await MusicService().fetchSongDetail(
          songId: widget.track.id.toString(),
          source: widget.track.source,
        );
        
        if (detail == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('获取歌曲信息失败')),
            );
            setState(() => _isDownloading = false);
          }
          return;
        }
        
        final success = await DownloadService().downloadSong(
          widget.track,
          detail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
        
        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载失败')),
            );
          }
        }
      } else {
        final success = await DownloadService().downloadSong(
          widget.track,
          songDetail,
          onProgress: (progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
        );
        
        if (mounted) {
          if (success) {
            setState(() {
              _isDownloaded = true;
              _isDownloading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${widget.track.name} 下载完成')),
            );
          } else {
            setState(() => _isDownloading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('下载失败或文件已存在')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Padding(
          padding: EdgeInsets.all(12.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    if (_isDownloading) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _progress,
              strokeWidth: 2,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
            Text(
              '${(_progress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      );
    }

    return IconButton(
      icon: Icon(
        _isDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
        color: _isDownloaded ? Colors.green : Colors.white.withOpacity(0.8),
      ),
      onPressed: _isDownloaded ? null : _startDownload,
      tooltip: _isDownloaded ? '已下载' : '下载',
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
