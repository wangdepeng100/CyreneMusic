import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/player_service.dart';
import '../../services/lyric_font_service.dart';
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
  bool _hasInitialScrolled = false; // 是否已完成首次滚动

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _previousIndex = widget.currentLyricIndex;
    // 监听字体变化，实时刷新
    LyricFontService().addListener(_onFontChanged);
  }

  @override
  void dispose() {
    LyricFontService().removeListener(_onFontChanged);
    _scrollResetTimer?.cancel();
    _timeCapsuleController.dispose();
    _spacingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
  
  /// 字体变化回调
  void _onFontChanged() {
    if (mounted) {
      setState(() {});
    }
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

  /// 滚动到指定索引（带动画）
  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients || _viewportHeight <= 0) return;
    
    // 如果有译文，增加行高30%
    final hasTranslation = _hasTranslation();
    final effectiveItemHeight = hasTranslation ? _itemHeight * 1.3 : _itemHeight;
    final targetOffset = index * effectiveItemHeight;
    
    // 使用弹性曲线滚动
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 700),
      curve: const _ElasticOutCurve(),
    );
  }
  
  /// 立即滚动到指定索引（无动画，用于首次进入）
  void _scrollToIndexImmediate(int index) {
    if (!_scrollController.hasClients || _viewportHeight <= 0) return;
    
    // 如果有译文，增加行高30%
    final hasTranslation = _hasTranslation();
    final effectiveItemHeight = hasTranslation ? _itemHeight * 1.3 : _itemHeight;
    final targetOffset = index * effectiveItemHeight;
    _scrollController.jumpTo(targetOffset);
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
        
        // 首次布局完成后，立即滚动到当前歌词位置
        if (!_hasInitialScrolled && _viewportHeight > 0) {
          _hasInitialScrolled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollToIndexImmediate(widget.currentLyricIndex);
            }
          });
        }

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
    final fontFamily = LyricFontService().currentFontFamily ?? 'Microsoft YaHei';
    return Center(
      child: Text(
        '纯音乐 / 暂无歌词',
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 42,
          fontWeight: FontWeight.w800,
          fontFamily: fontFamily,
        ),
      ),
    );
  }

  /// 检查歌词是否包含译文
  bool _hasTranslation() {
    if (!widget.showTranslation) return false;
    return widget.lyrics.any((lyric) => 
        lyric.translation != null && lyric.translation!.isNotEmpty);
  }

  /// 构建歌词列表
  Widget _buildLyricList() {
    // 如果有译文，增加行高30%
    final hasTranslation = _hasTranslation();
    final effectiveItemHeight = hasTranslation ? _itemHeight * 1.3 : _itemHeight;
    
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification && 
            notification.dragDetails != null) {
          // 用户开始拖动
          _activateManualScroll();
        } else if (notification is ScrollUpdateNotification && _isUserScrolling) {
          // 更新选中的歌词索引
          final centerOffset = _scrollController.offset + (_viewportHeight / 2);
          final index = (centerOffset / effectiveItemHeight).floor();
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
            itemExtent: effectiveItemHeight,
            padding: EdgeInsets.symmetric(vertical: (_viewportHeight - effectiveItemHeight) / 2),
            physics: const BouncingScrollPhysics(),
            cacheExtent: _viewportHeight,
            itemBuilder: (context, index) {
              return _buildLyricLine(index, effectiveItemHeight);
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
  Widget _buildLyricLine(int index, double effectiveItemHeight) {
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
          child: SizedBox(
            height: effectiveItemHeight,
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxHeight: effectiveItemHeight * 1.5, // 允许内容超出50%高度
              child: Padding(
                padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: opacity,
                  // 性能优化：仅在需要模糊时应用 ImageFiltered
                  child: _OptionalBlur(
                    blur: blur,
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
                            fontFamily: LyricFontService().currentFontFamily ?? 'Microsoft YaHei',
                            height: 1.25,
                            letterSpacing: -0.5,
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
                                return _KaraokeText(
                                  text: lyric.text,
                                  lyric: lyric,
                                  lyrics: widget.lyrics,
                                  index: index,
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
                                  fontFamily: LyricFontService().currentFontFamily ?? 'Microsoft YaHei',
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

/// 性能优化：条件应用模糊滤镜
/// blur=0 时直接返回子组件，避免不必要的滤镜开销
class _OptionalBlur extends StatelessWidget {
  final double blur;
  final Widget child;

  const _OptionalBlur({
    required this.blur,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    // 当 blur 接近 0 时，跳过滤镜操作
    if (blur < 0.1) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: child,
    );
  }
}

/// 卡拉OK文本组件 - 实现逐行填充效果
/// 性能优化：使用 Ticker 驱动动画，避免监听整个 PlayerService
class _KaraokeText extends StatefulWidget {
  final String text;
  final LyricLine lyric;
  final List<LyricLine> lyrics;
  final int index;

  const _KaraokeText({
    required this.text,
    required this.lyric,
    required this.lyrics,
    required this.index,
  });

  @override
  State<_KaraokeText> createState() => _KaraokeTextState();
}

class _KaraokeTextState extends State<_KaraokeText> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _progress = 0.0;
  
  // 布局测量缓存
  double _cachedMaxWidth = 0.0;
  TextStyle? _cachedStyle;
  List<LineMetrics>? _cachedLineMetrics;
  int _cachedLineCount = 1;
  double _line1Width = 0.0;
  double _line2Width = 0.0;
  double _line1Height = 0.0;
  double _line2Height = 0.0;
  double _line1Ratio = 0.5;
  
  // 计算歌词持续时间（缓存）
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _calculateDuration();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
  
  void _calculateDuration() {
    if (widget.index < widget.lyrics.length - 1) {
      _duration = widget.lyrics[widget.index + 1].startTime - widget.lyric.startTime;
    } else {
      _duration = const Duration(seconds: 5);
    }
    if (_duration.inMilliseconds == 0) _duration = const Duration(seconds: 3);
  }

  void _onTick(Duration elapsed) {
    final currentPos = PlayerService().position;
    final elapsedFromStart = currentPos - widget.lyric.startTime;
    final newProgress = (elapsedFromStart.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    
    // 仅在进度有显著变化时更新（减少不必要的重建）
    if ((newProgress - _progress).abs() > 0.005) {
      setState(() {
        _progress = newProgress;
      });
    }
  }
  
  /// 更新布局测量缓存
  void _updateLayoutCache(BoxConstraints constraints, TextStyle style) {
    if (_cachedMaxWidth == constraints.maxWidth && _cachedStyle == style) {
      return; // 缓存有效，无需重新测量
    }
    
    _cachedMaxWidth = constraints.maxWidth;
    _cachedStyle = style;
    
    final textSpan = TextSpan(text: widget.text, style: style);
    final textPainter = TextPainter(
      text: textSpan,
      maxLines: 2,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout(maxWidth: constraints.maxWidth);
    
    _cachedLineMetrics = textPainter.computeLineMetrics();
    _cachedLineCount = _cachedLineMetrics!.length.clamp(1, 2);
    
    _line1Width = _cachedLineMetrics![0].width;
    _line2Width = _cachedLineMetrics!.length > 1 ? _cachedLineMetrics![1].width : 0.0;
    _line1Height = _cachedLineMetrics![0].height;
    _line2Height = _cachedLineMetrics!.length > 1 ? _cachedLineMetrics![1].height : 0.0;
    
    final totalWidth = _line1Width + _line2Width;
    _line1Ratio = totalWidth > 0 ? _line1Width / totalWidth : 0.5;
    
    textPainter.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style;
        _updateLayoutCache(constraints, style);
        return _buildKaraokeEffect(style);
      },
    );
  }

  Widget _buildKaraokeEffect(TextStyle style) {
    if (_cachedLineCount == 1) {
      // 单行：使用 ShaderMask 实现高性能渐变
      return RepaintBoundary(
        child: ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: const [
                Colors.white,
                Color(0x73FFFFFF), // Colors.white.withOpacity(0.45)
              ],
              stops: [_progress, _progress],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: Text(widget.text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    
    // 多行：计算每行进度
    double line1Progress, line2Progress;
    if (_progress <= _line1Ratio) {
      line1Progress = _progress / _line1Ratio;
      line2Progress = 0.0;
    } else {
      line1Progress = 1.0;
      line2Progress = (_progress - _line1Ratio) / (1.0 - _line1Ratio);
    }
    
    // 底层暗色文本 (使用 const 颜色)
    final dimText = Text(
      widget.text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: const Color(0x73FFFFFF)),
    );
    
    // 上层亮色文本
    final brightText = Text(
      widget.text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: Colors.white),
    );
    
    return RepaintBoundary(
      child: Stack(
        children: [
          dimText,
          ClipRect(
            clipper: _LineClipper(
              lineIndex: 0,
              progress: line1Progress,
              lineHeight: _line1Height,
              lineWidth: _line1Width,
            ),
            child: brightText,
          ),
          if (_cachedLineCount > 1)
            ClipRect(
              clipper: _LineClipper(
                lineIndex: 1,
                progress: line2Progress,
                lineHeight: _line2Height + 10,
                lineWidth: _line2Width,
                yOffset: _line1Height,
              ),
              child: brightText,
            ),
        ],
      ),
    );
  }
}

/// 自定义裁剪器：用于裁剪单行文本的进度
class _LineClipper extends CustomClipper<Rect> {
  final int lineIndex;
  final double progress;
  final double lineHeight;
  final double lineWidth;
  final double yOffset;

  _LineClipper({
    required this.lineIndex,
    required this.progress,
    required this.lineHeight,
    required this.lineWidth,
    this.yOffset = 0.0,
  });

  @override
  Rect getClip(Size size) {
    // 裁剪该行从左到右的进度部分
    final clipWidth = lineWidth * progress;
    return Rect.fromLTWH(0, yOffset, clipWidth, lineHeight);
  }

  @override
  bool shouldReclip(_LineClipper oldClipper) {
    return oldClipper.progress != progress ||
           oldClipper.lineIndex != lineIndex ||
           oldClipper.lineHeight != lineHeight ||
           oldClipper.lineWidth != lineWidth ||
           oldClipper.yOffset != yOffset;
  }
}
