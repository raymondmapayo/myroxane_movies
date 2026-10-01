import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';
import '../viewmodels/home_view_model.dart';
import '../viewmodels/view_state.dart';
import '../widgets/media_widgets.dart';
import '../widgets/state_widgets.dart';
import 'navigation.dart';

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.onOpenSearch,
    required this.onOpenBrowse,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenBrowse;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<HomeViewModel>();
    return Scaffold(
      appBar: AppBar(
        title: const LantawMark(),
        actions: [
          IconButton(
            onPressed: onOpenSearch,
            tooltip: 'Search titles',
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: switch (viewModel.status) {
        ViewStatus.loading || ViewStatus.idle => const PageLoader(),
        ViewStatus.error => ErrorState(
          message: viewModel.errorMessage ?? 'Unknown error',
          onRetry: viewModel.load,
        ),
        _ => _HomeContent(viewModel: viewModel, onOpenBrowse: onOpenBrowse),
      },
    );
  }
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({required this.viewModel, required this.onOpenBrowse});
  final HomeViewModel viewModel;
  final VoidCallback onOpenBrowse;

  @override
  Widget build(BuildContext context) {
    final feed = viewModel.feed!;
    final spotlight = feed.spotlight;
    return RefreshIndicator(
      onRefresh: viewModel.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (spotlight != null)
            _SpotlightCard(media: spotlight, onBrowse: onOpenBrowse)
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: PageIntro(
                eyebrow: 'Start here',
                title: 'Find your next watch.',
                detail: 'Browse movies and series by genre or language.',
              ),
            ),
          const SizedBox(height: 24),
          _RailBlock(
            child: MediaRail(
              title: 'Trending movies',
              items: feed.popularMovies,
              type: MediaType.movie,
              onTap: (media) => openMediaDetails(context, media),
            ),
          ),
          const SizedBox(height: 30),
          _RailBlock(
            child: MediaRail(
              title: 'Binge-worthy series',
              items: feed.popularSeries,
              type: MediaType.tv,
              onTap: (media) => openMediaDetails(context, media),
            ),
          ),
          const SizedBox(height: 30),
          _RailBlock(
            child: MediaRail(
              title: 'Critically acclaimed',
              items: feed.highRatedMovies,
              type: MediaType.movie,
              onTap: (media) => openMediaDetails(context, media),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  const _SpotlightCard({required this.media, required this.onBrowse});
  final Media media;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(),
    child: InkWell(
      onTap: () => openMediaDetails(context, media),
      child: SizedBox(
        height: 470,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkArtwork(
              url: AppConfig.backdrop(media.backdropPath),
              icon: Icons.movie_outlined,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x33080808),
                    AppColors.midnight,
                  ],
                  stops: [0, .48, 1],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#1 FEATURED TODAY',
                    style: AppTheme.utility(
                      size: 10,
                      color: AppColors.projector,
                      weight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.display(38),
                  ),
                  if (media.overview.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      media.overview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.45,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => openMediaDetails(context, media),
                          icon: const Icon(Icons.info_outline_rounded),
                          label: const Text('View details'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xB34B4B4B),
                            foregroundColor: AppColors.ink,
                          ),
                          onPressed: onBrowse,
                          icon: const Icon(Icons.grid_view_rounded),
                          label: const Text('Browse'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RailBlock extends StatelessWidget {
  const _RailBlock({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: child,
  );
}
