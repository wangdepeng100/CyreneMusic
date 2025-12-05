part of 'my_page.dart';

/// Material UI 构建方法
extension MyPageMaterialUI on _MyPageState {
  Widget _buildMaterialPage(BuildContext context, ColorScheme colorScheme, bool isLoggedIn) {
    if (!isLoggedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 80, color: colorScheme.primary.withOpacity(0.5)),
            const SizedBox(height: 24),
            Text('登录后查看更多', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('登录即可管理歌单和查看听歌统计', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showAuthDialog(context).then((_) { refresh(); }),
              icon: const Icon(Icons.login),
              label: const Text('立即登录'),
            ),
          ],
        ),
      );
    }

    if (_selectedPlaylist != null) {
      return _buildMaterialPlaylistDetail(_selectedPlaylist!, colorScheme);
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _playlistService.loadPlaylists();
        await _loadStats();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMaterialUserCard(colorScheme),
          const SizedBox(height: 16),
          _buildMaterialStatsCard(colorScheme),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('我的歌单', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.cloud_download), onPressed: _showImportPlaylistDialog, tooltip: '从网易云导入歌单'),
                  TextButton.icon(onPressed: _showCreatePlaylistDialog, icon: const Icon(Icons.add), label: const Text('新建')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMaterialPlaylistsList(colorScheme),
          const SizedBox(height: 24),
          if (_statsData != null && _statsData!.playCounts.isNotEmpty) ...[
            const Text('播放排行榜 Top 10', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMaterialTopPlaysList(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialUserCard(ColorScheme colorScheme) {
    final user = AuthService().currentUser;
    if (user == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: user.avatarUrl != null ? CachedNetworkImageProvider(user.avatarUrl!) : null,
              child: user.avatarUrl == null ? Text(user.username[0].toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.username, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(user.email, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface.withOpacity(0.6))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialStatsCard(ColorScheme colorScheme) {
    if (_isLoadingStats) {
      return const Card(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())));
    }

    if (_statsData == null) {
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('暂无统计数据', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)))));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('听歌统计', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMaterialStatItem(icon: Icons.access_time, label: '累计时长', value: ListeningStatsService.formatDuration(_statsData!.totalListeningTime), colorScheme: colorScheme)),
                const SizedBox(width: 16),
                Expanded(child: _buildMaterialStatItem(icon: Icons.play_circle_outline, label: '播放次数', value: '${_statsData!.totalPlayCount} 次', colorScheme: colorScheme)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialStatItem({required IconData icon, required String label, required String value, required ColorScheme colorScheme}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildMaterialPlaylistsList(ColorScheme colorScheme) {
    final playlists = _playlistService.playlists;

    if (playlists.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.library_music_outlined, size: 48, color: colorScheme.onSurface.withOpacity(0.3)),
                const SizedBox(height: 16),
                Text('暂无歌单', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: playlists.map((playlist) {
        final canSync = _hasImportConfig(playlist);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _buildMaterialPlaylistCover(playlist, colorScheme),
            title: Text(playlist.name),
            subtitle: Text('${playlist.trackCount} 首歌曲'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!playlist.isDefault) ...[
                  IconButton(icon: const Icon(Icons.sync, size: 20), color: canSync ? colorScheme.primary : null, onPressed: canSync ? () => _syncPlaylistFromList(playlist) : null, tooltip: canSync ? '同步歌单' : '请先设置导入来源'),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), color: Colors.redAccent, onPressed: () => _confirmDeletePlaylist(playlist), tooltip: '删除歌单'),
                ],
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => _openPlaylistDetail(playlist),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMaterialPlaylistCover(Playlist playlist, ColorScheme colorScheme) {
    if (playlist.coverUrl != null && playlist.coverUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: playlist.coverUrl!,
          width: 48, height: 48, fit: BoxFit.cover,
          placeholder: (_, __) => Container(width: 48, height: 48, decoration: BoxDecoration(color: playlist.isDefault ? colorScheme.primaryContainer : colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(playlist.isDefault ? Icons.favorite : Icons.library_music, color: playlist.isDefault ? Colors.red : colorScheme.primary)),
          errorWidget: (_, __, ___) => Container(width: 48, height: 48, decoration: BoxDecoration(color: playlist.isDefault ? colorScheme.primaryContainer : colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(playlist.isDefault ? Icons.favorite : Icons.library_music, color: playlist.isDefault ? Colors.red : colorScheme.primary)),
        ),
      );
    }
    return Container(width: 48, height: 48, decoration: BoxDecoration(color: playlist.isDefault ? colorScheme.primaryContainer : colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(8)), child: Icon(playlist.isDefault ? Icons.favorite : Icons.library_music, color: playlist.isDefault ? Colors.red : colorScheme.primary));
  }

  Widget _buildMaterialTopPlaysList(ColorScheme colorScheme) {
    final topPlays = _statsData!.playCounts.take(10).toList();
    return Card(
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: topPlays.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = topPlays[index];
          final rank = index + 1;
          Color? rankColor;
          if (rank == 1) rankColor = Colors.amber;
          else if (rank == 2) rankColor = Colors.grey.shade400;
          else if (rank == 3) rankColor = Colors.brown.shade300;

          return ListTile(
            leading: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: item.picUrl, width: 48, height: 48, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(width: 48, height: 48, color: colorScheme.surfaceContainerHighest, child: const Icon(Icons.music_note)),
                    errorWidget: (_, __, ___) => Container(width: 48, height: 48, color: colorScheme.surfaceContainerHighest, child: const Icon(Icons.music_note)),
                  ),
                ),
                Positioned(left: 0, top: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: rankColor ?? colorScheme.primary, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), bottomRight: Radius.circular(4))), child: Text('$rank', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)))),
              ],
            ),
            title: Text(item.trackName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(item.artists, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${item.playCount} 次', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(item.toTrack().getSourceName(), style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withOpacity(0.5))),
              ],
            ),
            onTap: () => _playTrack(item),
          );
        },
      ),
    );
  }

  Widget _buildMaterialPlaylistDetail(Playlist playlist, ColorScheme colorScheme) {
    final allTracks = _playlistService.currentPlaylistId == playlist.id ? _playlistService.currentTracks : <PlaylistTrack>[];
    final isLoading = _playlistService.isLoadingTracks;
    final filteredTracks = _filterTracks(allTracks);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          _buildMaterialDetailAppBar(playlist, colorScheme, allTracks),
          if (_isSearchMode) SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: _buildMaterialSearchField(colorScheme))),
          if (isLoading && allTracks.isEmpty)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (allTracks.isEmpty)
            SliverFillRemaining(child: _buildMaterialDetailEmptyState(colorScheme))
          else if (filteredTracks.isEmpty && _searchQuery.isNotEmpty)
            SliverFillRemaining(child: _buildMaterialSearchEmptyState(colorScheme))
          else ...[
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(16.0), child: _buildMaterialDetailStatsCard(colorScheme, filteredTracks.length, totalCount: allTracks.length))),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
                final track = filteredTracks[index];
                final originalIndex = allTracks.indexOf(track);
                return _buildMaterialTrackItem(track, originalIndex, colorScheme);
              }, childCount: filteredTracks.length)),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
        ],
      ),
    );
  }

  Widget _buildMaterialSearchField(ColorScheme colorScheme) {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: '搜索歌曲、歌手、专辑...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); _onSearchChanged(''); }) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: _onSearchChanged,
      autofocus: true,
    );
  }

  Widget _buildMaterialSearchEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('未找到匹配的歌曲', style: TextStyle(fontSize: 16, color: colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text('尝试其他关键词', style: TextStyle(fontSize: 14, color: colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildMaterialDetailAppBar(Playlist playlist, ColorScheme colorScheme, List<PlaylistTrack> tracks) {
    return SliverAppBar(
      floating: true, snap: true,
      backgroundColor: colorScheme.surface,
      leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _backToList),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_isEditMode ? '已选择 ${_selectedTrackIds.length} 首' : playlist.name, style: TextStyle(color: colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
          if (!_isEditMode && playlist.isDefault) Text('默认歌单', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
        ],
      ),
      actions: [
        if (_isEditMode) ...[
          IconButton(icon: Icon(_selectedTrackIds.length == tracks.length ? Icons.check_box : Icons.check_box_outline_blank), onPressed: tracks.isNotEmpty ? _toggleSelectAll : null, tooltip: _selectedTrackIds.length == tracks.length ? '取消全选' : '全选'),
          IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: _selectedTrackIds.isNotEmpty ? _batchRemoveTracks : null, tooltip: '删除选中'),
          TextButton(onPressed: _toggleEditMode, child: const Text('取消')),
        ] else ...[
          if (tracks.isNotEmpty) IconButton(icon: Icon(_isSearchMode ? Icons.search_off : Icons.search), onPressed: _toggleSearchMode, tooltip: _isSearchMode ? '关闭搜索' : '搜索歌曲'),
          if (tracks.isNotEmpty) IconButton(icon: const Icon(Icons.swap_horiz), onPressed: () => _showSourceSwitchDialog(playlist, tracks), tooltip: '换源'),
          if (tracks.isNotEmpty) IconButton(icon: const Icon(Icons.edit), onPressed: _toggleEditMode, tooltip: '批量管理'),
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () async {
              if (!_hasImportConfig(playlist)) {
                _showUserNotification('请先在"导入管理"中绑定来源后再同步', severity: fluent.InfoBarSeverity.warning);
                return;
              }
              _showUserNotification('正在同步...', duration: const Duration(seconds: 1));
              final result = await _playlistService.syncPlaylist(playlist.id);
              _showUserNotification(_formatSyncResultMessage(result), severity: result.insertedCount > 0 ? fluent.InfoBarSeverity.success : fluent.InfoBarSeverity.info);
              await _playlistService.loadPlaylistTracks(playlist.id);
            },
            tooltip: '同步',
          ),
        ],
      ],
    );
  }

  Widget _buildMaterialDetailStatsCard(ColorScheme colorScheme, int count, {int? totalCount}) {
    final String countText = (totalCount != null && totalCount != count) ? '筛选出 $count / 共 $totalCount 首歌曲' : '共 $count 首歌曲';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(Icons.music_note, size: 24, color: colorScheme.primary),
            const SizedBox(width: 12),
            Text(countText, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (count > 0) FilledButton.icon(onPressed: _playAll, icon: const Icon(Icons.play_arrow, size: 20), label: const Text('播放全部')),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialDetailEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_off, size: 64, color: colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('歌单为空', style: TextStyle(fontSize: 16, color: colorScheme.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Text('快去添加一些喜欢的歌曲吧', style: TextStyle(fontSize: 14, color: colorScheme.onSurface.withOpacity(0.5))),
        ],
      ),
    );
  }

  Widget _buildMaterialTrackItem(PlaylistTrack item, int index, ColorScheme colorScheme) {
    final trackKey = _getTrackKey(item);
    final isSelected = _selectedTrackIds.contains(trackKey);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected && _isEditMode ? colorScheme.primaryContainer.withOpacity(0.3) : null,
      child: ListTile(
        leading: _isEditMode
            ? Checkbox(value: isSelected, onChanged: (_) => _toggleTrackSelection(item))
            : Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: item.picUrl, width: 50, height: 50, fit: BoxFit.cover,
                      placeholder: (_, __) => Container(width: 50, height: 50, color: colorScheme.surfaceContainerHighest, child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
                      errorWidget: (_, __, ___) => Container(width: 50, height: 50, color: colorScheme.surfaceContainerHighest, child: Icon(Icons.music_note, color: colorScheme.onSurfaceVariant)),
                    ),
                  ),
                  Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: colorScheme.primaryContainer, borderRadius: const BorderRadius.only(topLeft: Radius.circular(4))), child: Text('#${index + 1}', style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 10, fontWeight: FontWeight.bold)))),
                ],
              ),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Expanded(child: Text('${item.artists} • ${item.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 8),
            Text(_getSourceIcon(item.source), style: const TextStyle(fontSize: 12)),
          ],
        ),
        trailing: _isEditMode ? null : Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.play_arrow), onPressed: () => _playDetailTrack(index), tooltip: '播放'),
            IconButton(icon: const Icon(Icons.remove_circle_outline, size: 20), color: Colors.redAccent, onPressed: () => _confirmRemoveTrack(item), tooltip: '从歌单移除'),
          ],
        ),
        onTap: _isEditMode ? () => _toggleTrackSelection(item) : () => _playDetailTrack(index),
      ),
    );
  }
}
