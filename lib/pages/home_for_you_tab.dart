import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import '../services/netease_recommend_service.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';
import 'home_page/daily_recommend_detail_page.dart';
import 'discover_playlist_detail_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../utils/theme_manager.dart';
import '../services/weather_service.dart';

/// 首页 - 为你推荐 Tab 内容
class HomeForYouTab extends StatefulWidget {
  const HomeForYouTab({super.key, this.onOpenPlaylistDetail, this.onOpenDailyDetail});

  final void Function(int playlistId)? onOpenPlaylistDetail;
  final void Function(List<Map<String, dynamic>> tracks)? onOpenDailyDetail;

  @override
  State<HomeForYouTab> createState() => _HomeForYouTabState();
}

class _HomeForYouTabState extends State<HomeForYouTab> {
  late Future<_ForYouData> _future;
  
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ForYouData> _load() async {
    // 1) 先尝试读取当日缓存
    final prefs = await SharedPreferences.getInstance();
    final cacheBase = _cacheBaseKey();
    final dataKey = '${cacheBase}_data';
    final expireKey = '${cacheBase}_expire';
    final now = DateTime.now();
    final expireMs = prefs.getInt(expireKey);
    if (expireMs != null && now.millisecondsSinceEpoch < expireMs) {
      final jsonString = prefs.getString(dataKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        try {
          final data = _ForYouData.fromJsonString(jsonString);
          return data;
        } catch (_) {
          // 解析失败，继续走网络请求
        }
      }
    }

    // 2) 拉取网络数据（聚合接口，一次性并发获取）
    final svc = NeteaseRecommendService();
    final combined = await svc.fetchForYouCombined(personalizedLimit: 12, newsongLimit: 10);
    final result = _ForYouData(
      dailySongs: combined['dailySongs'] ?? const [],
      fm: combined['fm'] ?? const [],
      dailyPlaylists: combined['dailyPlaylists'] ?? const [],
      personalizedPlaylists: combined['personalizedPlaylists'] ?? const [],
      radarPlaylists: combined['radarPlaylists'] ?? const [],
      personalizedNewsongs: combined['personalizedNewsongs'] ?? const [],
    );

    // 3) 写入当日缓存（有效期至当日 23:59:59）
    try {
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      await prefs.setString(dataKey, result.toJsonString());
      await prefs.setInt(expireKey, endOfDay.millisecondsSinceEpoch);
    } catch (_) {}

    return result;
  }

  String _cacheBaseKey() {
    final userId = AuthService().currentUser?.id?.toString() ?? 'guest';
    return 'home_for_you_$userId';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    
    return FutureBuilder<_ForYouData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: isCupertino 
                  ? const CupertinoActivityIndicator(radius: 14)
                  : const CircularProgressIndicator(),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(child: Padding(padding: const EdgeInsets.all(24.0), child: Text('加载失败：${snapshot.error ?? ''}')));
        }
        final data = snapshot.data!;
        return Stack(
          children: [
            Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _GreetingHeader(),
                  _DailyRecommendCard(
                    tracks: data.dailySongs,
                  onOpenDetail: () => widget.onOpenDailyDetail?.call(data.dailySongs),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(title: '私人FM'),
                  _PersonalFm(list: data.fm),
                  const SizedBox(height: 24),
                  _SectionTitle(title: '每日推荐歌单'),
                  _PlaylistGrid(
                    list: data.dailyPlaylists,
                    onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(title: '专属歌单'),
                  _PlaylistGrid(
                    list: data.personalizedPlaylists,
                    onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(title: '雷达歌单'),
                  _PlaylistGrid(
                    list: data.radarPlaylists,
                    onTap: (id) => widget.onOpenPlaylistDetail?.call(id),
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(title: '个性化新歌'),
                  _NewsongList(list: data.personalizedNewsongs),
                  const SizedBox(height: 16),
                ],
            ),

          ],
        );
      },
    );
  }
}

class _ForYouData {
  final List<Map<String, dynamic>> dailySongs;
  final List<Map<String, dynamic>> fm;
  final List<Map<String, dynamic>> dailyPlaylists;
  final List<Map<String, dynamic>> personalizedPlaylists;
  final List<Map<String, dynamic>> radarPlaylists;
  final List<Map<String, dynamic>> personalizedNewsongs;
  _ForYouData({
    required this.dailySongs,
    required this.fm,
    required this.dailyPlaylists,
    required this.personalizedPlaylists,
    required this.radarPlaylists,
    required this.personalizedNewsongs,
  });

  Map<String, dynamic> toJson() => {
        'dailySongs': dailySongs,
        'fm': fm,
        'dailyPlaylists': dailyPlaylists,
        'personalizedPlaylists': personalizedPlaylists,
        'radarPlaylists': radarPlaylists,
        'personalizedNewsongs': personalizedNewsongs,
      };

  String toJsonString() => jsonEncode(toJson());

  static _ForYouData fromJson(Map<String, dynamic> json) {
    return _ForYouData(
      dailySongs: (json['dailySongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      fm: (json['fm'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      dailyPlaylists: (json['dailyPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedPlaylists: (json['personalizedPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      radarPlaylists: (json['radarPlaylists'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
      personalizedNewsongs: (json['personalizedNewsongs'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>(),
    );
  }

  static _ForYouData fromJsonString(String s) {
    final map = jsonDecode(s) as Map<String, dynamic>;
    return fromJson(map);
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title, 
        style: isCupertino
            ? const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              )
            : Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// 顶部问候语（根据时间段变化）
class _GreetingHeader extends StatelessWidget {
  const _GreetingHeader();

  String _greetText(TimeOfDay now) {
    final minutes = now.hour * 60 + now.minute;
    if (minutes < 6 * 60) return '夜深了';            // 00:00 - 05:59
    if (minutes < 9 * 60) return '早上好';            // 06:00 - 08:59
    if (minutes < 12 * 60) return '上午好';           // 09:00 - 11:59
    if (minutes < 14 * 60) return '中午好';           // 12:00 - 13:59
    if (minutes < 18 * 60) return '下午好';           // 14:00 - 17:59
    return '晚上好';                                  // 18:00 - 23:59
  }

  String _subGreeting(TimeOfDay now) {
    final h = now.hour;
    if (h < 6) return '注意休息，音乐轻声一点';
    if (h < 9) return '新的一天，从此开始好心情';
    if (h < 12) return '愿音乐伴你高效工作';
    if (h < 14) return '午后小憩，来点轻松的旋律';
    if (h < 18) return '忙碌之余，听听喜欢的歌';
    return '夜色温柔，音乐更动听';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final now = TimeOfDay.now();
    final greet = _greetText(now);
    final sub = _subGreeting(now);

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(
            isCupertino ? CupertinoIcons.sun_max_fill : Icons.wb_twilight_rounded, 
            color: isCupertino ? ThemeManager.iosBlue : cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greet,
                  style: isCupertino 
                      ? const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        )
                      : Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: isCupertino 
                      ? TextStyle(
                          fontSize: 14,
                          color: CupertinoColors.systemGrey,
                        )
                      : Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FutureBuilder<String?>(
            future: WeatherService().fetchWeatherText(),
            builder: (context, snap) {
              final txt = snap.data?.toString();
              if (txt == null || txt.isEmpty) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isCupertino ? CupertinoIcons.sun_max : Icons.wb_sunny_rounded, 
                    size: 16, 
                    color: isCupertino ? CupertinoColors.systemGrey : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      txt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: isCupertino
                          ? TextStyle(
                              fontSize: 14,
                              color: CupertinoColors.systemGrey,
                            )
                          : Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 每日推荐卡片（点击跳转到详情页）
class _DailyRecommendCard extends StatelessWidget {
  final List<Map<String, dynamic>> tracks;
  final VoidCallback? onOpenDetail;
  const _DailyRecommendCard({required this.tracks, this.onOpenDetail});
  
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 获取前4首歌曲的封面
    final coverImages = tracks.take(4).map((s) {
      final al = (s['al'] ?? s['album'] ?? {}) as Map<String, dynamic>;
      return (al['picUrl'] ?? '').toString();
    }).where((url) => url.isNotEmpty).toList();
    
    // iOS 26 Cupertino 风格 - 液态玻璃卡片
    if (isCupertino) {
      return _buildCupertinoCard(context, coverImages, isDark);
    }
    
    final cardContent = _buildMaterialCardContent(context, coverImages, cs);

    if (themeManager.isFluentFramework) {
      return fluent.Card(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6.0),
          child: cardContent,
        ),
      );
    }
    
    return Card(
      clipBehavior: Clip.antiAlias,
      color: cs.surfaceContainerHighest,
      child: cardContent,
    );
  }
  
  /// iOS 26 风格的卡片（不使用 BackdropFilter 避免滚动渲染问题）
  Widget _buildCupertinoCard(BuildContext context, List<String> coverImages, bool isDark) {
    final now = DateTime.now();
    final dayOfMonth = now.day;
    final weekday = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][now.weekday % 7];
    
    // 获取主封面
    final mainCover = coverImages.isNotEmpty ? coverImages.first : '';
    
    return GestureDetector(
      onTap: () {
        if (onOpenDetail != null) {
          onOpenDetail!();
        } else {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (context) => DailyRecommendDetailPage(tracks: tracks),
            ),
          );
        }
      },
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          // 与私人FM保持一致的背景色
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部：标题
                Text(
                  '每日推荐',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
                const Spacer(),
                // 底部：日期 + 信息 + 播放按钮
                Row(
                  children: [
                    // 左侧：日期卡片
                    _buildDateBadge(context, dayOfMonth, weekday, isDark),
                    const SizedBox(width: 16),
                    // 中间：信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '根据你的品味生成',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? Colors.white.withOpacity(0.7)
                                  : Colors.black.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${tracks.length} 首歌曲',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.45),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // 封面缩略图
                          _buildCoverThumbnails(context, coverImages, isDark),
                        ],
                      ),
                    ),
                    // 播放按钮
                    _buildPlayButton(context, isDark),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 日期徽章
  Widget _buildDateBadge(BuildContext context, int day, String weekday, bool isDark) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.08),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            day.toString().padLeft(2, '0'),
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: ThemeManager.iosBlue,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            weekday,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? Colors.white.withOpacity(0.6)
                  : Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 封面缩略图
  Widget _buildCoverThumbnails(BuildContext context, List<String> coverImages, bool isDark) {
    final displayCovers = coverImages.take(4).toList();
    
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          // 叠加的封面图
          ...List.generate(displayCovers.length, (index) {
            return Transform.translate(
              offset: Offset(-index * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? Colors.black.withOpacity(0.3)
                        : Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: displayCovers[index].isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: displayCovers[index],
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark
                              ? const Color(0xFF3A3A3C)
                              : const Color(0xFFE5E5EA),
                          child: Icon(
                            CupertinoIcons.music_note,
                            size: 16,
                            color: isDark
                                ? Colors.white.withOpacity(0.5)
                                : Colors.black.withOpacity(0.3),
                          ),
                        ),
                ),
              ),
            );
          }),
          // 剩余数量标识
          if (tracks.length > 4)
            Transform.translate(
              offset: Offset(-displayCovers.length * 12.0, 0),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.15)
                      : Colors.black.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '+${tracks.length - 4}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? Colors.white.withOpacity(0.8)
                          : Colors.black.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  /// 播放按钮
  Widget _buildPlayButton(BuildContext context, bool isDark) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeManager.iosBlue,
            ThemeManager.iosBlue.withBlue(230),
          ],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ThemeManager.iosBlue.withOpacity(0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        CupertinoIcons.play_fill,
        color: Colors.white,
        size: 24,
      ),
    );
  }
  
  /// Material 风格卡片内容
  Widget _buildMaterialCardContent(BuildContext context, List<String> coverImages, ColorScheme cs) {
    return InkWell(
      onTap: () {
        if (onOpenDetail != null) {
          onOpenDetail!();
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => DailyRecommendDetailPage(tracks: tracks),
            ),
          );
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool isNarrow = constraints.maxWidth < 480;
          final EdgeInsets contentPadding = const EdgeInsets.all(16);
          if (isNarrow) {
            final double gridSize = (constraints.maxWidth * 0.38).clamp(120.0, 180.0);
            return Padding(
              padding: contentPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: gridSize,
                    height: gridSize,
                    child: _buildCoverGrid(context, coverImages),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '每日推荐',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tracks.length} 首歌曲',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(0.65),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.auto_awesome, size: 18, color: cs.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                '根据你的音乐品味每日更新',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: FilledButton.icon(
                              onPressed: () {
                                if (onOpenDetail != null) {
                                  onOpenDetail!();
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.chevron_right, size: 20),
                              label: const Text('查看全部'),
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

          return Container(
            height: 200,
            padding: contentPadding.add(const EdgeInsets.all(4)),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  height: 160,
                  child: _buildCoverGrid(context, coverImages),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '每日推荐',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${tracks.length} 首歌曲',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 16,
                            color: cs.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 20,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '根据你的音乐品味每日更新',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: cs.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: FilledButton.icon(
                            onPressed: () {
                              if (onOpenDetail != null) {
                                onOpenDetail!();
                              } else {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => DailyRecommendDetailPage(tracks: tracks),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.chevron_right, size: 20),
                            label: const Text(
                              '查看全部',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  /// 构建封面网格（2x2）- Material 风格
  Widget _buildCoverGrid(BuildContext context, List<String> coverImages) {
    final cs = Theme.of(context).colorScheme;
    final covers = List<String>.from(coverImages);
    
    while (covers.length < 4) {
      covers.add('');
    }
    
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final url = covers[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url.isEmpty
              ? Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.music_note,
                    color: cs.onSurface.withOpacity(0.3),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.music_note,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(
                      Icons.broken_image,
                      color: cs.onSurface.withOpacity(0.3),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _PersonalFm extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _PersonalFm({required this.list});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return AnimatedBuilder(
      animation: PlayerService(),
      builder: (context, _) {
        // 选择展示的歌曲：优先显示当前播放且属于此FM列表的歌曲，否则显示第一首
        Map<String, dynamic> display = list.first;
        final current = PlayerService().currentTrack;
        if (current != null && current.source == MusicSource.netease) {
          for (final m in list) {
            final id = (m['id'] ?? (m['song'] != null ? (m['song'] as Map<String, dynamic>)['id'] : null)) as dynamic;
            if (id != null && id.toString() == current.id.toString()) {
              display = m;
              break;
            }
          }
        }

        final album = (display['album'] ?? display['al'] ?? {}) as Map<String, dynamic>;
        final artists = (display['artists'] ?? display['ar'] ?? []) as List<dynamic>;
        final artistsText = artists.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        final pic = (album['picUrl'] ?? '').toString();

        // 仅当当前播放或当前队列属于此FM列表时，才把状态视为“播放中”
        final fmTracks = _convertListToTracks(list);
        final isFmCurrent = _currentTrackInList(fmTracks);
        final isFmQueue = _isSameQueueAs(fmTracks);
        final isFmPlaying = PlayerService().isPlaying && (isFmCurrent || isFmQueue);

        final cardContent = Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(pic, width: 120, height: 120, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(display['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Text(artistsText, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  isCupertino 
                      ? CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            final ps = PlayerService();
                            if (isFmPlaying) {
                              await ps.pause();
                            } else if (ps.isPaused && (isFmQueue || isFmCurrent)) {
                              await ps.resume();
                            } else {
                              PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
                              await ps.playTrack(tracks.first);
                            }
                          },
                          child: Icon(
                            isFmPlaying ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, 
                            color: ThemeManager.iosBlue,
                            size: 28,
                          ),
                        )
                      : IconButton(
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            final ps = PlayerService();
                            if (isFmPlaying) {
                              await ps.pause();
                            } else if (ps.isPaused && (isFmQueue || isFmCurrent)) {
                              await ps.resume();
                            } else {
                              PlaylistQueueService().setQueue(tracks, 0, QueueSource.playlist);
                              await ps.playTrack(tracks.first);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('开始播放私人FM')),
                                );
                              }
                            }
                          },
                          style: IconButton.styleFrom(
                            hoverColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            focusColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                            overlayColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(isFmPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: cs.onSurface),
                          tooltip: isFmPlaying ? '暂停' : '播放',
                        ),
                  const SizedBox(width: 8),
                  isCupertino 
                      ? CupertinoButton(
                          padding: const EdgeInsets.all(8),
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            if (_isSameQueueAs(tracks)) {
                              await PlayerService().playNext();
                            } else {
                              final startIndex = tracks.length > 1 ? 1 : 0;
                              PlaylistQueueService().setQueue(tracks, startIndex, QueueSource.playlist);
                              await PlayerService().playTrack(tracks[startIndex]);
                            }
                          },
                          child: Icon(
                            CupertinoIcons.forward_fill, 
                            color: ThemeManager.iosBlue,
                            size: 28,
                          ),
                        )
                      : IconButton(
                          onPressed: () async {
                            final tracks = fmTracks;
                            if (tracks.isEmpty) return;
                            if (_isSameQueueAs(tracks)) {
                              await PlayerService().playNext();
                            } else {
                              final startIndex = tracks.length > 1 ? 1 : 0;
                              PlaylistQueueService().setQueue(tracks, startIndex, QueueSource.playlist);
                              await PlayerService().playTrack(tracks[startIndex]);
                            }
                          },
                          style: IconButton.styleFrom(
                            hoverColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                            focusColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                            overlayColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(Icons.skip_next_rounded, color: cs.onSurface),
                          tooltip: '下一首',
                        ),
                ],
              ),
            ],
          ),
        );

        if (themeManager.isFluentFramework) {
          return fluent.Card(
            padding: EdgeInsets.zero,
            child: cardContent,
          );
        }

        // Cupertino 风格卡片
        if (isCupertino) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: cardContent,
          );
        }

        return Card(
          color: cs.surfaceContainer,
          child: cardContent,
        );
      },
    );
  }

  List<Track> _convertListToTracks(List<Map<String, dynamic>> src) {
    return src.map((m) => _convertToTrack(m)).toList();
  }

  Track _convertToTrack(Map<String, dynamic> song) {
    final album = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
    final artists = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
    return Track(
      id: song['id'] ?? 0,
      name: song['name']?.toString() ?? '',
      artists: artists
          .map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .join(' / '),
      album: album['name']?.toString() ?? '',
      picUrl: album['picUrl']?.toString() ?? '',
      source: MusicSource.netease,
    );
  }

  bool _isSameQueueAs(List<Track> tracks) {
    final q = PlaylistQueueService().queue;
    if (q.length != tracks.length) return false;
    for (var i = 0; i < q.length; i++) {
      if (q[i].id.toString() != tracks[i].id.toString() || q[i].source != tracks[i].source) {
        return false;
      }
    }
    return true;
  }

  bool _currentTrackInList(List<Track> tracks) {
    final ct = PlayerService().currentTrack;
    if (ct == null) return false;
    return tracks.any((t) => t.id.toString() == ct.id.toString() && t.source == ct.source);
  }
}

class _PlaylistGrid extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  final void Function(int id)? onTap;
  const _PlaylistGrid({required this.list, this.onTap});
  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final p = list[i];
        final pic = (p['picUrl'] ?? p['coverImgUrl'] ?? '').toString();
        final idVal = p['id'];
        final id = int.tryParse(idVal?.toString() ?? '');
        return InkWell(
          onTap: id != null && onTap != null ? () => onTap!(id) : null,
          child: _HoverPlaylistCard(
            name: p['name']?.toString() ?? '',
            picUrl: pic,
            description: (p['description'] ?? p['copywriter'] ?? '').toString(),
          ),
        );
      },
    );
  }
}

class _HoverPlaylistCard extends StatefulWidget {
  final String name;
  final String picUrl;
  final String description;
  const _HoverPlaylistCard({required this.name, required this.picUrl, required this.description});

  @override
  State<_HoverPlaylistCard> createState() => _HoverPlaylistCardState();
}

class _HoverPlaylistCardState extends State<_HoverPlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: _hovering
              ? [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : [],
        ),
        child: isCupertino
            ? Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SizedBox.expand(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOut,
                                scale: _hovering ? 1.10 : 1.0,
                                child: CachedNetworkImage(
                                  imageUrl: widget.picUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: CupertinoColors.systemGrey6,
                                    child: const Icon(
                                      CupertinoIcons.music_note,
                                      color: CupertinoColors.systemGrey,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: CupertinoColors.systemGrey6,
                                    child: const Icon(
                                      CupertinoIcons.exclamationmark_circle,
                                      color: CupertinoColors.systemGrey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: AnimatedSlide(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                offset: _hovering ? Offset.zero : const Offset(0, 1),
                                child: FractionallySizedBox(
                                  widthFactor: 1.0,
                                  heightFactor: 0.38,
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.0),
                                          Colors.black.withOpacity(0.65),
                                        ],
                                      ),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                    child: Align(
                                      alignment: Alignment.bottomLeft,
                                      child: Text(
                                        (widget.description.isNotEmpty ? widget.description : widget.name),
                                        style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            widget.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: themeManager.isFluentFramework ? null : cs.surfaceContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 封面图片（容器固定，内部放大10%）
                      SizedBox.expand(
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOut,
                          scale: _hovering ? 1.10 : 1.0,
                          child: CachedNetworkImage(
                            imageUrl: widget.picUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.music_note,
                                color: cs.onSurface.withOpacity(0.3),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.broken_image,
                                color: cs.onSurface.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 自底部滑出的渐变遮罩 + 描述
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          offset: _hovering ? Offset.zero : const Offset(0, 1),
                          child: FractionallySizedBox(
                            widthFactor: 1.0,
                            heightFactor: 0.38,
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.0),
                                    Colors.black.withOpacity(0.65),
                                  ],
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Text(
                                  (widget.description.isNotEmpty ? widget.description : widget.name),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.2),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Text(
                      widget.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsongList extends StatelessWidget {
  final List<Map<String, dynamic>> list;
  const _NewsongList({required this.list});
  @override
  Widget build(BuildContext context) {
    final themeManager = ThemeManager();
    final isCupertino = (Platform.isIOS || Platform.isAndroid) && themeManager.isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (list.isEmpty) return Text('暂无数据', style: Theme.of(context).textTheme.bodySmall);
    
    if (isCupertino) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(isDark ? 0.2 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(
            height: 0.5,
            color: isDark 
                ? CupertinoColors.systemGrey.withOpacity(0.3)
                : CupertinoColors.systemGrey.withOpacity(0.2),
          ),
          itemBuilder: (context, i) {
            final s = list[i];
            final song = (s['song'] ?? s);
            final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
            final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
            final pic = (al['picUrl'] ?? '').toString();
            final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
            return CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () {
                // TODO: Play this song
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6), 
                      child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song['name']?.toString() ?? '', 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            artists, 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemGrey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: CupertinoColors.systemGrey,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final s = list[i];
        final song = (s['song'] ?? s);
        final al = (song['al'] ?? song['album'] ?? {}) as Map<String, dynamic>;
        final ar = (song['ar'] ?? song['artists'] ?? []) as List<dynamic>;
        final pic = (al['picUrl'] ?? '').toString();
        final artists = ar.map((e) => (e as Map<String, dynamic>)['name']?.toString() ?? '').where((e) => e.isNotEmpty).join('/');
        return ListTile(
          leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(pic, width: 48, height: 48, fit: BoxFit.cover)),
          title: Text(song['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }
}


