part of 'track_metadata_screen.dart';

extension _TrackMetadataMornye on _TrackMetadataScreenState {
  Widget _buildMornyePage(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artwork = resolveMetadataArtworkSource(
      embeddedCoverPath:
          _embeddedCoverPreviewPath ??
          DownloadedEmbeddedCoverResolver.resolve(_filePath),
      localCoverPath: _localCoverPath,
      remoteCoverUrl: _coverUrl,
    );
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      child: Scaffold(
        body: CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              centerTitle: true,
              title: Text(context.l10n.trackMetadata),
              leadingWidth: 64,
              leading: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: HeaderCircleButton(
                  icon: CupertinoIcons.chevron_back,
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: _popWithMetadataResult,
                ),
              ),
              actionsPadding: const EdgeInsets.only(right: 16),
              actions: [
                Builder(
                  builder: (buttonContext) => HeaderCircleButton(
                    icon: CupertinoIcons.ellipsis,
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                    onPressed: () => _showOptionsMenu(
                      context,
                      ref,
                      scheme,
                      anchor: mornyeMenuAnchor(buttonContext),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: adaptiveContentMaxWidth(
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Hero(
                              tag: _coverHeroTag,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox.square(
                                  dimension: 70,
                                  child: PlayerArtwork(
                                    artUri: artwork,
                                    colorScheme: scheme,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ExplicitTrackTitle(
                                    title: trackName,
                                    explicit: isExplicit,
                                    style: theme.textTheme.titleLarge,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    artistName,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (albumName.trim().isNotEmpty)
                                    Text(
                                      albumName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_hasCheckedFile && !_fileExists)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              context.l10n.trackFileNotFound,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: adaptiveContentMaxWidth(
                      MediaQuery.sizeOf(context).width,
                    ),
                  ),
                  child: _buildAnimatedTrackContent(context, ref, scheme),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: context.navBarBottomInset),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metadataSectionSurface(
    BuildContext context,
    ColorScheme scheme, {
    required Widget child,
  }) {
    if (context.isMornye) {
      return Material(
        color: MornyeTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: DividerTheme(
          data: DividerTheme.of(
            context,
          ).copyWith(color: MornyeTheme.metadataDividerColor(context)),
          child: child,
        ),
      );
    }
    return Card(
      elevation: 0,
      color: settingsGroupColor(context),
      shape: _sectionCardShape(scheme),
      child: child,
    );
  }
}
