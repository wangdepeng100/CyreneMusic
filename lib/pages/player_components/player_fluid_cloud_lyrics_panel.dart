import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../services/player_service.dart';
import '../../models/lyric_line.dart';


/// 核心：弹性间距动画 + 波浪式延迟
class PlayerFluidCloudLyricsPanel extends StatefulWidget {
  final List<LyricLine> lyrics;
  final int currentLyricIndex;
  final bool showTranslation;

  const PlayerFluidCloudLyricsPanel({
    super.key,
    required this.lyrics,
    required this.currentLyricIndex,
    required this.showTranslation,
  });

  @override
  State<PlayerFluidCloudLyricsPanel> createState() => _PlayerFluidCloudLyricsPanelState();
}

class _PlayerFluidCloudLyricsPanelState extends State<PlayerFluidCloudLyricsPanel> 
    with TickerProviderStateMixin {
  
  // ===== 滚动控制 =====
  final ScrollController _scrollController = ScrollController();
  int? _selectedLyricIndex;
  bool _isUserScrolling = false;
  Timer? _scrollResetTimer;
  
  // ===== 动画控制 =====
  late AnimationController _timeCapsuleController;
  late Animation<double> _timeCapsuleFade;
  
  // ===== 弹性间距动画 =====
  late AnimationController _spacingController;
  int _previousIndex = -1;
  
  // ===== 布局缓存 =====
  double _itemHeight = 100.0;
  double _viewportHeight = 0.0;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _previousIndex = widget.currentLyricIndex;
  }

  @override
  void dispose() {
    _scrollResetTimer?.cancel();
    _timeCapsuleController.dispose();
    _spacingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initAnimations() {
    _timeCapsuleController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _timeCapsuleFade = CurvedAnimation(
      parent: _timeCapsuleController,
      curve: Curves.easeInOut,
    );
    
    // 弹性间距动画控制器
    _spacingController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(PlayerFluidCloudLyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 歌词索引变化且非手动滚动模式时
    if (widget.currentLyricIndex != oldWidget.currentLyricIndex && !_isUserScrolling) {
      _previousIndex = oldWidget.currentLyricIndex;
      // 触发弹性动画
      _spacingController.forward(from: 0.0);
      _scrollToIndex(widget.currentLyricIndex);
    }
  }

  /// 滚动到指定索引
  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients || _viewportHeight <= 0) return;
    
    final targetOffset = index * _itemHeight;
    
    // 使用弹性曲线滚动
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 700),
      curve: const _ElasticOutCurve(),
    );
  }

  /// 激活手动滚动模式
  void _activateManualScroll() {
    if (!_isUserScrolling) {
      setState(() {
        _isUserScrolling = true;
      });
      _timeCapsuleController.forward();
    }
    _resetScrollTimer();
  }

  /// 重置滚动定时器
  void _resetScrollTimer() {
    _scrollResetTimer?.cancel();
    _scrollResetTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _isUserScrolling = false;
          _selectedLyricIndex = null;
        });
        _timeCapsuleController.reverse();
        // 回到当前播放位置
        _scrollToIndex(widget.currentLyricIndex);
      }
    });
  }

  /// 跳转到选中的歌词
  void _seekToSelectedLyric() {
    if (_selectedLyricIndex != null && 
        _selectedLyricIndex! >= 0 && 
        _selectedLyricIndex! < widget.lyrics.length) {
      final lyric = widget.lyrics[_selectedLyricIndex!];
      PlayerService().seek(lyric.startTime);
    }
    
    setState(() {
      _isUserScrolling = false;
      _selectedLyricIndex = null;
    });
    _timeCapsuleController.reverse();
    _scrollResetTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lyrics.isEmpty) {
      return _buildNoLyric();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        // 可视区域显示约 7 行歌词
        _itemHeight = _viewportHeight / 7;

        return Stack(
          children: [
            // 歌词列表
            _buildLyricList(),
            
            // 时间胶囊 (手动滚动时显示)
            if (_isUserScrolling && _selectedLyricIndex != null)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(child: _buildTimeCapsule()),
              ),
          ],
        );
      },
    );
  }

  /// 构建无歌词提示
  Widget _buildNoLyric() {
    return Center(
      child: Text(
        '纯音乐 / 暂无歌词',
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 42,
          fontWeight: FontWeight.w800,
          fontFamily: 'Microsoft YaHei',
        ),
      ),
    );
  }

  /// 构建歌词列表
  Widget _buildLyricList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && 
            notification.dragDetails != null) {
          // 用户开始拖动
          _activateManualScroll();
        } else if (notification is ScrollUpdateNotification && _isUserScrolling) {
          // 更新选中的歌词索引
          final centerOffset = _scrollController.offset + (_viewportHeight / 2);
          final index = (centerOffset / _itemHeight).floor();
          if (index >= 0 && index < widget.lyrics.length && index != _selectedLyricIndex) {
            setState(() {
              _selectedLyricIndex = index;
            });
          }
          _resetScrollTimer();
        }
        return false;
      },
      child: AnimatedBuilder(
        animation: _spacingController,
        builder: (context, child) {
          return ListView.builder(
            controller: _scrollController,
            itemCount: widget.lyrics.length,
            itemExtent: _itemHeight,
            padding: EdgeInsets.symmetric(vertical: (_viewportHeight - _itemHeight) / 2),
            physics: const BouncingScrollPhysics(),
            cacheExtent: _viewportHeight,
            itemBuilder: (context, index) {
              return _buildLyricLine(index);
            },
          );
        },
      ),
    );
  }

  /// 获取弹性偏移量 
  double _getElasticOffset(int index) {
    if (_isUserScrolling) return 0.0;
    
    final currentIndex = widget.currentLyricIndex;
    final diff = index - currentIndex;
    
    // 只对当前行附近的几行应用弹性效果
    if (diff.abs() > 5) return 0.0;
    
    // 计算延迟：距离越远延迟越大
    // 模拟波浪效果
    final delay = (diff.abs() * 0.08).clamp(0.0, 0.4);
    
    // 调整动画进度，考虑延迟
    final adjustedProgress = ((_spacingController.value - delay) / (1.0 - delay)).clamp(0.0, 1.0);
    
    // 弹性曲线：先过冲再回弹
    final elasticValue = const _ElasticOutCurve().transform(adjustedProgress);
    
    // 间距变化量：模拟滚动时的间距拉伸
    // 初始时刻(progress=0)间距最大，然后弹回正常
    final spacingChange = 24.0 * (1.0 - elasticValue);
    
    // diff > 0 (下方): 向下偏移 (+)
    // diff < 0 (上方): 向上偏移 (-)
    // 这样中间就被拉开了
    return spacingChange * diff;
  }

  /// 构建单行歌词 - Apple Music 风格
  Widget _buildLyricLine(int index) {
    final lyric = widget.lyrics[index];
    final isActive = index == widget.currentLyricIndex;
    final isSelected = _isUserScrolling && _selectedLyricIndex == index;
    final distance = (index - widget.currentLyricIndex).abs();
    
    // ===== 视觉参数计算 
    // 透明度：当前行 1.0，距离越远越透明
    final opacity = isActive ? 1.0 : (1.0 - distance * 0.15).clamp(0.3, 0.8);
    
    // 模糊度：当前行清晰，距离越远越模糊 
    final blur = isActive ? 0.0 : (distance * 1.0).clamp(0.0, 2.0);
    
    // ===== 弹性偏移 =====
    final elasticOffset = _getElasticOffset(index);
    
    // 译文的弹性偏移 (仅对当前行生效，使其与原文之间也有弹性效果)
    // 延迟稍大一点，产生波浪感
    double translationOffset = 0.0;
    if (isActive && !_isUserScrolling) {
      final progress = _spacingController.value;
      // 弹性曲线
      final elasticValue = const _ElasticOutCurve().transform(progress);
      // 间距变化量：初始间距较大，然后弹回
      translationOffset = 4.0 * (1.0 - elasticValue);
    }
    
    final bottomPadding = isActive ? 16.0 : 8.0;

    return GestureDetector(
      onTap: () {
        // 点击歌词跳转
        PlayerService().seek(lyric.startTime);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Transform.translate(
          // 弹性 Y 轴偏移
          offset: Offset(0, elasticOffset),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            height: _itemHeight,
            // 动态间距：active 行底部间距更大
            padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
            alignment: Alignment.centerLeft,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: opacity,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 原文歌词
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: isSelected 
                            ? Colors.orange 
                            : (isActive ? Colors.white : Colors.white.withOpacity(0.45)),
                        fontSize: isActive ? 32 : 26,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Microsoft YaHei',
                        height: 1.25,
                        letterSpacing: -0.5,
                        shadows: isActive ? [
                          Shadow(
                            color: Colors.white.withOpacity(0.3),
                            blurRadius: 20,
                          ),
                        ] : null,
                      ),
                      child: Builder(
                        builder: (context) {
                          final textWidget = Text(
                            lyric.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          );
                          
                          // 只有当前行且非手动滚动时才启用卡拉OK效果
                          if (isActive && !_isUserScrolling) {
                            return AnimatedBuilder(
                              animation: PlayerService(),
                              builder: (context, child) {
                                final player = PlayerService();
                                final currentPos = player.position;
                                
                                // 计算持续时间
                                Duration duration;
                                if (index < widget.lyrics.length - 1) {
                                  duration = widget.lyrics[index + 1].startTime - lyric.startTime;
                                } else {
                                  duration = const Duration(seconds: 5); // 最后一行默认时长
                                }
                                
                                // 防止除以零
                                if (duration.inMilliseconds == 0) duration = const Duration(seconds: 3);
                                
                                final elapsed = currentPos - lyric.startTime;
                                final progress = (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
                                
                                return ShaderMask(
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      colors: [
                                        Colors.white, 
                                        Colors.white.withOpacity(0.45)
                                      ],
                                      stops: [progress, progress], // 硬边缘扫描
                                      tileMode: TileMode.clamp,
                                    ).createShader(bounds);
                                  },
                                  blendMode: BlendMode.srcIn,
                                  child: textWidget,
                                );
                              },
                            );
                          }
                          
                          return textWidget;
                        },
                      ),
                    ),
                    
                    // 翻译歌词
                    if (widget.showTranslation && 
                        lyric.translation != null && 
                        lyric.translation!.isNotEmpty)
                      Transform.translate(
                        offset: Offset(0, translationOffset),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: TextStyle(
                              color: isActive 
                                  ? Colors.white.withOpacity(0.9) 
                                  : Colors.white.withOpacity(0.6),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Microsoft YaHei',
                              height: 1.3,
                            ),
                            child: Text(
                              lyric.translation!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建时间胶囊
  Widget _buildTimeCapsule() {
    if (_selectedLyricIndex == null || 
        _selectedLyricIndex! < 0 || 
        _selectedLyricIndex! >= widget.lyrics.length) {
      return const SizedBox.shrink();
    }

    final lyric = widget.lyrics[_selectedLyricIndex!];
    final timeText = _formatDuration(lyric.startTime);

    return FadeTransition(
      opacity: _timeCapsuleFade,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _seekToSelectedLyric,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Consolas',
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '点击跳转',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// 弹性曲线
/// 这是一个过冲曲线，值会超过 1.0 然后回弹
class _ElasticOutCurve extends Curve {
  const _ElasticOutCurve();

  @override
  double transformInternal(double t) {
    // 使用简化的弹性公式
    final t2 = t - 1.0;
    // 过冲系数 1.56 产生弹性效果
    return 1.0 + t2 * t2 * ((1.56 + 1) * t2 + 1.56);
  }
}
