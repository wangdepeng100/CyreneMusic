import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import '../utils/theme_manager.dart';
import '../services/netease_artist_service.dart';
import '../services/player_service.dart';
import '../models/track.dart';
import 'album_detail_page.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ArtistDetailPage extends StatefulWidget {
  final int artistId;
  const ArtistDetailPage({super.key, required this.artistId});

  @override
  State<ArtistDetailPage> createState() => _ArtistDetailPageState();
}

class _ArtistDetailPageState extends State<ArtistDetailPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  bool get _isCupertino => ThemeManager().isCupertinoFramework;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await NeteaseArtistDetailService().fetchArtistDetail(widget.artistId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      if (data == null) _error = '加载失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;

    if (isFluent) {
      final useWindowEffect =
          Platform.isWindows && ThemeManager().windowEffect != WindowEffect.disabled;
      final body = ArtistDetailContent(artistId: widget.artistId);
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('歌手详情'),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: useWindowEffect
            ? body
            : Container(
                color: fluent.FluentTheme.of(context).micaBackgroundColor,
                child: body,
              ),
      );
    }

    // iOS Cupertino 风格
    if (_isCupertino) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return CupertinoPageScaffold(
        backgroundColor: isDark 
            ? const Color(0xFF000000) 
            : CupertinoColors.systemGroupedBackground,
        navigationBar: CupertinoNavigationBar(
          middle: const Text('歌手详情'),
          backgroundColor: isDark 
              ? const Color(0xFF1C1C1E).withOpacity(0.9) 
              : CupertinoColors.white.withOpacity(0.9),
        ),
        child: ArtistDetailContent(artistId: widget.artistId),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('歌手详情'),
        backgroundColor: cs.surface,
      ),
      body: ArtistDetailContent(artistId: widget.artistId),
    );
  }
}

/// 胶囊样式 Tabs
class _CapsuleTabs extends StatelessWidget {
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;
  const _CapsuleTabs({required this.tabs, required this.currentIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    final fluentTheme = fluent.FluentTheme.maybeOf(context);
    final isFluent = fluentTheme != null;
    final isCupertino = ThemeManager().isCupertinoFramework;

    // iOS Cupertino 风格：使用分段控件
    if (isCupertino) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: currentIndex,
          children: {
            for (int i = 0; i < tabs.length; i++)
              i: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  tabs[i],
                  style: const TextStyle(fontSize: 14),
                ),
              ),
          },
          onValueChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final bg = isFluent
        ? (fluentTheme!.resources?.controlAltFillColorSecondary ??
            Colors.black.withOpacity(0.05))
        : cs.surfaceContainerHighest;
    final pillColor = isFluent
        ? fluentTheme!.accentColor.defaultBrushFor(
            fluentTheme.brightness,
          )
        : cs.primary;
    final selFg = isFluent
        ? fluentTheme!.resources?.textOnAccentFillColorPrimary ?? Colors.white
        : cs.onPrimary;
    final unSelFg = isFluent
        ? fluentTheme!.resources?.textFillColorSecondary ??
            Colors.white.withOpacity(0.8)
        : cs.onSurfaceVariant;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = 48.0; // 提高高度
        final padding = 5.0;
        final radius = height / 2;
        final totalWidth = constraints.maxWidth;
        final count = tabs.length;
        final tabWidth = totalWidth / count;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              // 背景容器
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
              ),
              // 滑动胶囊指示器（位置与大小均有动画）
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                top: padding,
                bottom: padding,
                left: padding + currentIndex * (tabWidth - padding * 2),
                width: tabWidth - padding * 2,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(radius - padding),
                    boxShadow: [
                      BoxShadow(
                        color: pillColor.withOpacity(0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              // 标签点击与文字
              Row(
                children: List.generate(count, (i) {
                  final selected = i == currentIndex;
                  final tabContent = Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      style: TextStyle(
                        color: selected ? selFg : unSelFg,
                        fontWeight: FontWeight.w600,
                      ),
                      child: Text(tabs[i]),
                    ),
                  );
                  return SizedBox(
                    width: tabWidth,
                    height: height,
                    child: isFluent
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onChanged(i),
                            child: tabContent,
                          )
                        : InkWell(
                            borderRadius: BorderRadius.circular(radius),
                            onTap: () => onChanged(i),
                            child: tabContent,
                          ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _buildAdaptiveCard({
  required bool isFluent,
  required bool isCupertino,
  required bool isDark,
  EdgeInsetsGeometry? margin,
  EdgeInsetsGeometry? padding,
  required Widget child,
}) {
  if (isFluent) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: fluent.Card(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }
  if (isCupertino) {
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Container(
        padding: padding ?? EdgeInsets.zero,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
    );
  }
  return Card(
    margin: margin,
    child: padding != null ? Padding(padding: padding, child: child) : child,
  );
}

Widget _buildAdaptiveListTile({
  required bool isFluent,
  required bool isCupertino,
  required bool isDark,
  Widget? leading,
  Widget? title,
  Widget? subtitle,
  Widget? trailing,
  VoidCallback? onPressed,
}) {
  if (isFluent) {
    return fluent.ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onPressed: onPressed,
    );
  }
  if (isCupertino) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[
              leading,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark ? CupertinoColors.white : CupertinoColors.black,
                      ),
                      child: title,
                    ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                      ),
                      child: subtitle,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
  return ListTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onPressed,
  );
}

Widget _buildAdaptiveProgressIndicator(bool isFluent, bool isCupertino) {
  if (isFluent) {
    return const fluent.ProgressRing();
  }
  if (isCupertino) {
    return const CupertinoActivityIndicator(radius: 14);
  }
  return const CircularProgressIndicator();
}

class _SongsListView extends StatelessWidget {
  final List<dynamic> songs;
  final bool isFluent;
  final bool isCupertino;
  final bool isDark;
  const _SongsListView({
    super.key, 
    required this.songs, 
    required this.isFluent,
    required this.isCupertino,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Text(
          '暂无歌曲', 
          style: isCupertino
              ? TextStyle(color: CupertinoColors.systemGrey)
              : Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    
    // iOS Cupertino 风格：使用圆角卡片容器
    if (isCupertino) {
      final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
      return ListView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: bottomPadding),
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (int i = 0; i < songs.length; i++) ...[
                  _buildCupertinoSongTile(context, songs[i] as Map<String, dynamic>),
                  if (i < songs.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 78),
                      child: Container(
                        height: 0.5,
                        color: CupertinoColors.systemGrey.withOpacity(0.3),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return ListView.builder(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final m = songs[index] as Map<String, dynamic>;
        final track = Track(
          id: m['id'],
          name: m['name']?.toString() ?? '',
          artists: m['artists']?.toString() ?? '',
          album: m['album']?.toString() ?? '',
          picUrl: m['picUrl']?.toString() ?? '',
          source: MusicSource.netease,
        );
        final trailing = isFluent
            ? const fluent.Icon(fluent.FluentIcons.play)
            : const Icon(Icons.play_arrow);

        return _buildAdaptiveCard(
          isFluent: isFluent,
          isCupertino: isCupertino,
          isDark: isDark,
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.zero,
          child: _buildAdaptiveListTile(
            isFluent: isFluent,
            isCupertino: isCupertino,
            isDark: isDark,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CachedNetworkImage(
                imageUrl: track.picUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
              ),
            ),
            title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${track.artists} • ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: trailing,
            onPressed: () => PlayerService().playTrack(track),
          ),
        );
      },
    );
  }
  
  Widget _buildCupertinoSongTile(BuildContext context, Map<String, dynamic> m) {
    final track = Track(
      id: m['id'],
      name: m['name']?.toString() ?? '',
      artists: m['artists']?.toString() ?? '',
      album: m['album']?.toString() ?? '',
      picUrl: m['picUrl']?.toString() ?? '',
      source: MusicSource.netease,
    );
    
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () => PlayerService().playTrack(track),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track.picUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 50,
                  height: 50,
                  color: isDark 
                      ? const Color(0xFF2C2C2E) 
                      : CupertinoColors.systemGrey5,
                  child: const Center(
                    child: CupertinoActivityIndicator(radius: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${track.artists} • ${track.album}',
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
              CupertinoIcons.play_fill,
              color: CupertinoColors.activeBlue,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumsListView extends StatelessWidget {
  final List<dynamic> albums;
  final void Function(int albumId)? onOpenAlbum;
  final bool isFluent;
  final bool isCupertino;
  final bool isDark;
  const _AlbumsListView({
    super.key, 
    required this.albums, 
    this.onOpenAlbum, 
    required this.isFluent,
    required this.isCupertino,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          '暂无专辑', 
          style: isCupertino
              ? TextStyle(color: CupertinoColors.systemGrey)
              : Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    
    // iOS Cupertino 风格
    if (isCupertino) {
      final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
      return ListView(
        padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: bottomPadding),
        children: [
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                for (int i = 0; i < albums.length; i++) ...[
                  _buildCupertinoAlbumTile(context, albums[i] as Map<String, dynamic>),
                  if (i < albums.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 84),
                      child: Container(
                        height: 0.5,
                        color: CupertinoColors.systemGrey.withOpacity(0.3),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      );
    }
    
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return ListView.builder(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
      itemCount: albums.length,
      itemBuilder: (context, index) {
        final a = albums[index] as Map<String, dynamic>;
        final cover = (a['coverImgUrl'] ?? '') as String;
        final trailing = isFluent
            ? const fluent.Icon(fluent.FluentIcons.chevron_right_small)
            : const Icon(Icons.chevron_right);
        return _buildAdaptiveCard(
          isFluent: isFluent,
          isCupertino: isCupertino,
          isDark: isDark,
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.zero,
          child: _buildAdaptiveListTile(
            isFluent: isFluent,
            isCupertino: isCupertino,
            isDark: isDark,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(imageUrl: cover, width: 56, height: 56, fit: BoxFit.cover),
            ),
            title: Text(a['name']?.toString() ?? ''),
            subtitle: Text((a['company']?.toString() ?? '').isEmpty ? '' : a['company'].toString()),
            trailing: trailing,
            onPressed: () {
              final id = (a['id'] as num?)?.toInt();
              if (id != null) {
                if (onOpenAlbum != null) {
                  onOpenAlbum!(id);
                } else {
                  Navigator.of(context).push(
                    isFluent
                        ? fluent.FluentPageRoute(builder: (_) => AlbumDetailPage(albumId: id))
                        : MaterialPageRoute(builder: (_) => AlbumDetailPage(albumId: id)),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }
  
  Widget _buildCupertinoAlbumTile(BuildContext context, Map<String, dynamic> a) {
    final cover = (a['coverImgUrl'] ?? '') as String;
    final name = a['name']?.toString() ?? '';
    final company = (a['company']?.toString() ?? '').isEmpty ? '' : a['company'].toString();
    
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        final id = (a['id'] as num?)?.toInt();
        if (id != null) {
          if (onOpenAlbum != null) {
            onOpenAlbum!(id);
          } else {
            Navigator.of(context).push(
              CupertinoPageRoute(builder: (_) => AlbumDetailPage(albumId: id)),
            );
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: cover,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 56,
                  height: 56,
                  color: isDark 
                      ? const Color(0xFF2C2C2E) 
                      : CupertinoColors.systemGrey5,
                  child: const Center(
                    child: CupertinoActivityIndicator(radius: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? CupertinoColors.white : CupertinoColors.black,
                    ),
                  ),
                  if (company.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      company,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_forward,
              color: CupertinoColors.systemGrey,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _SongsThumbView extends StatelessWidget {
  final List<dynamic> songs;
  final bool isFluent;
  final bool isCupertino;
  final bool isDark;
  const _SongsThumbView({
    super.key, 
    required this.songs, 
    required this.isFluent,
    required this.isCupertino,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return Center(
        child: Text(
          '暂无歌曲', 
          style: isCupertino
              ? TextStyle(color: CupertinoColors.systemGrey)
              : Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: bottomPadding),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: songs.map((s0) {
          final m = s0 as Map<String, dynamic>;
          final name = m['name']?.toString() ?? '';
          final artists = m['artists']?.toString() ?? '';
          final album = m['album']?.toString() ?? '';
          final pic = m['picUrl']?.toString() ?? '';
          final track = Track(id: m['id'], name: name, artists: artists, album: album, picUrl: pic, source: MusicSource.netease);
          
          final trailing = isFluent
              ? const fluent.Icon(fluent.FluentIcons.play)
              : isCupertino
                  ? Icon(CupertinoIcons.play_fill, color: CupertinoColors.activeBlue, size: 20)
                  : const Icon(Icons.play_arrow);
          
          final cardContent = Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: pic, width: 80, height: 80, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCupertino 
                            ? (isDark ? CupertinoColors.white : CupertinoColors.black) 
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      artists, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: isCupertino 
                          ? TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)
                          : Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: isCupertino 
                          ? TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)
                          : Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          );
          final card = _buildAdaptiveCard(
            isFluent: isFluent,
            isCupertino: isCupertino,
            isDark: isDark,
            padding: const EdgeInsets.all(10),
            child: cardContent,
          );
          final tapHandler = () => PlayerService().playTrack(track);

          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 440),
            child: isFluent
                ? GestureDetector(
                    onTap: tapHandler,
                    child: card,
                  )
                : isCupertino
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: tapHandler,
                        child: card,
                      )
                    : InkWell(
                        onTap: tapHandler,
                        borderRadius: BorderRadius.circular(12),
                        child: card,
                      ),
          );
        }).toList(),
      ),
    );
  }
}

class _AlbumsThumbView extends StatelessWidget {
  final List<dynamic> albums;
  final void Function(int albumId)? onOpenAlbum;
  final bool isFluent;
  final bool isCupertino;
  final bool isDark;
  const _AlbumsThumbView({
    super.key, 
    required this.albums, 
    this.onOpenAlbum, 
    required this.isFluent,
    required this.isCupertino,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return Center(
        child: Text(
          '暂无专辑', 
          style: isCupertino
              ? TextStyle(color: CupertinoColors.systemGrey)
              : Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    final bottomPadding = MediaQuery.of(context).padding.bottom + 100;
    return SingleChildScrollView(
      padding: EdgeInsets.only(left: 16, right: 16, top: 8, bottom: bottomPadding),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: albums.map((a0) {
          final a = a0 as Map<String, dynamic>;
          final id = (a['id'] as num?)?.toInt();
          final cover = (a['coverImgUrl'] ?? '') as String;
          final name = (a['name'] ?? '').toString();
          final sub = (a['company'] ?? '').toString();
          
          final trailing = isFluent
              ? const fluent.Icon(fluent.FluentIcons.chevron_right_small)
              : isCupertino
                  ? Icon(CupertinoIcons.chevron_forward, color: CupertinoColors.systemGrey, size: 18)
                  : const Icon(Icons.chevron_right);
          
          final cardContent = Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: cover, width: 80, height: 80, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isCupertino 
                            ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      sub, 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                      style: isCupertino
                          ? TextStyle(fontSize: 13, color: CupertinoColors.systemGrey)
                          : Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          );
          final card = _buildAdaptiveCard(
            isFluent: isFluent,
            isCupertino: isCupertino,
            isDark: isDark,
            padding: const EdgeInsets.all(10),
            child: cardContent,
          );
          void handleTap() {
            if (id != null) {
              if (onOpenAlbum != null) {
                onOpenAlbum!(id);
              } else {
                Navigator.of(context).push(
                  isFluent
                      ? fluent.FluentPageRoute(builder: (_) => AlbumDetailPage(albumId: id))
                      : isCupertino
                          ? CupertinoPageRoute(builder: (_) => AlbumDetailPage(albumId: id))
                          : MaterialPageRoute(builder: (_) => AlbumDetailPage(albumId: id)),
                );
              }
            }
          }

          return ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 440),
            child: isFluent
                ? GestureDetector(onTap: handleTap, child: card)
                : isCupertino
                    ? CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: handleTap,
                        child: card,
                      )
                    : InkWell(
                        onTap: handleTap,
                        borderRadius: BorderRadius.circular(12),
                        child: card,
                      ),
          );
        }).toList(),
      ),
    );
  }
}
/// 无 AppBar 的内容组件，供悬浮窗使用
class ArtistDetailContent extends StatefulWidget {
  final int artistId;
  final void Function(int albumId)? onOpenAlbum;
  const ArtistDetailContent({super.key, required this.artistId, this.onOpenAlbum});

  @override
  State<ArtistDetailContent> createState() => _ArtistDetailContentState();
}

class _ArtistDetailContentState extends State<ArtistDetailContent> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  int _tabIndex = 0; // 0: 歌曲, 1: 专辑
  bool _useGrid = false; // false: 列表, true: 缩略图

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final data = await NeteaseArtistDetailService().fetchArtistDetail(widget.artistId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
      if (data == null) _error = '加载失败';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFluent = fluent.FluentTheme.maybeOf(context) != null;
    final isCupertino = ThemeManager().isCupertinoFramework;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_loading) {
      return Center(child: _buildAdaptiveProgressIndicator(isFluent, isCupertino));
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: isCupertino 
              ? TextStyle(color: CupertinoColors.systemGrey) 
              : null,
        ),
      );
    }
    
    final artist = _data!['artist'] as Map<String, dynamic>? ?? {};
    final albums = (_data!['albums'] as List<dynamic>? ?? []) as List<dynamic>;
    final songs = (_data!['songs'] as List<dynamic>? ?? []) as List<dynamic>;
    final imageUrl = (artist['img1v1Url'] ?? artist['picUrl'] ?? '') as String;
    
    Widget avatar;
    if (isFluent) {
      avatar = fluent.CircleAvatar(
        radius: 36,
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty
            ? const fluent.Icon(fluent.FluentIcons.contact)
            : null,
      );
    } else if (isCupertino) {
      avatar = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.systemGrey5,
          image: imageUrl.isNotEmpty 
              ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
              : null,
        ),
        child: imageUrl.isEmpty 
            ? Icon(CupertinoIcons.person_fill, size: 36, color: CupertinoColors.systemGrey)
            : null,
      );
    } else {
      avatar = CircleAvatar(
        radius: 36,
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
      );
    }
    
    final headerContent = Row(
      children: [
        avatar,
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                artist['name']?.toString() ?? '', 
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.w600,
                  color: isCupertino 
                      ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                      : null,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                artist['briefDesc']?.toString() ?? artist['description']?.toString() ?? '', 
                maxLines: 2, 
                overflow: TextOverflow.ellipsis,
                style: isCupertino
                    ? TextStyle(fontSize: 14, color: CupertinoColors.systemGrey)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );

    return Column(
      children: [
        // 顶部信息
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: (isFluent || isCupertino)
              ? _buildAdaptiveCard(
                  isFluent: isFluent,
                  isCupertino: isCupertino,
                  isDark: isDark,
                  padding: const EdgeInsets.all(16),
                  child: headerContent,
                )
              : headerContent,
        ),

        // 胶囊 Tabs / iOS 分段控件
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _CapsuleTabs(
            tabs: const ['歌曲', '专辑'],
            currentIndex: _tabIndex,
            onChanged: (i) => setState(() => _tabIndex = i),
          ),
        ),

        const SizedBox(height: 8),

        // 视图模式切换（列表/缩略图）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: _buildViewModeToggle(context, isFluent, isCupertino, isDark),
        ),

        // 内容列表
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _tabIndex == 0
                ? (_useGrid
                    ? _SongsThumbView(
                        key: const ValueKey('artist_songs_grid'), 
                        songs: songs, 
                        isFluent: isFluent,
                        isCupertino: isCupertino,
                        isDark: isDark,
                      )
                    : _SongsListView(
                        key: const ValueKey('artist_songs_list'), 
                        songs: songs, 
                        isFluent: isFluent,
                        isCupertino: isCupertino,
                        isDark: isDark,
                      ))
                : (_useGrid
                    ? _AlbumsThumbView(
                        key: const ValueKey('artist_albums_grid'),
                        albums: albums,
                        onOpenAlbum: widget.onOpenAlbum,
                        isFluent: isFluent,
                        isCupertino: isCupertino,
                        isDark: isDark,
                      )
                    : _AlbumsListView(
                        key: const ValueKey('artist_albums_list'),
                        albums: albums,
                        onOpenAlbum: widget.onOpenAlbum,
                        isFluent: isFluent,
                        isCupertino: isCupertino,
                        isDark: isDark,
                      )),
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeToggle(BuildContext context, bool isFluent, bool isCupertino, bool isDark) {
    if (isFluent) {
      final fluentTheme = fluent.FluentTheme.of(context);
      final iconColor = fluentTheme.resources?.textFillColorSecondary ?? Colors.grey;
      final labelStyle = fluentTheme.typography?.bodyStrong?.copyWith(
            color: fluentTheme.resources?.textFillColorSecondary,
          ) ??
          const TextStyle();
      return Row(
        children: [
          Icon(Icons.view_list, size: 18, color: iconColor),
          const SizedBox(width: 8),
          fluent.ToggleSwitch(
            checked: _useGrid,
            onChanged: (v) => setState(() => _useGrid = v),
            content: Text(_useGrid ? '缩略图' : '列表'),
          ),
          const SizedBox(width: 8),
          Icon(Icons.grid_view, size: 18, color: iconColor),
          const Spacer(),
          Text(_useGrid ? '缩略图' : '列表', style: labelStyle),
        ],
      );
    }
    
    if (isCupertino) {
      return Row(
        children: [
          Icon(CupertinoIcons.list_bullet, size: 18, color: CupertinoColors.systemGrey),
          const SizedBox(width: 8),
          CupertinoSwitch(
            value: _useGrid,
            onChanged: (v) => setState(() => _useGrid = v),
          ),
          const SizedBox(width: 8),
          Icon(CupertinoIcons.square_grid_2x2, size: 18, color: CupertinoColors.systemGrey),
          const Spacer(),
          Text(
            _useGrid ? '缩略图' : '列表', 
            style: TextStyle(
              fontSize: 13, 
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      );
    }

    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.view_list, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Switch(
          value: _useGrid,
          onChanged: (v) => setState(() => _useGrid = v),
        ),
        const SizedBox(width: 8),
        Icon(Icons.grid_view, size: 18, color: cs.onSurfaceVariant),
        const Spacer(),
        Text(_useGrid ? '缩略图' : '列表', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}


