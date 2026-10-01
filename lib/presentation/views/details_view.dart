import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';
import '../../domain/entities/media_details.dart';
import '../viewmodels/details_view_model.dart';
import '../viewmodels/view_state.dart';
import '../widgets/media_widgets.dart';
import '../widgets/state_widgets.dart';
import 'navigation.dart';
import 'player_view.dart';

class DetailsView extends StatelessWidget {
  const DetailsView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<DetailsViewModel>();
    return Scaffold(
      body: switch (viewModel.status) {
        ViewStatus.loading || ViewStatus.idle => const PageLoader(),
        ViewStatus.error => SafeArea(
          child: ErrorState(
            message: viewModel.errorMessage ?? 'Unknown error',
            onRetry: viewModel.load,
          ),
        ),
        _ => _DetailsContent(details: viewModel.details!),
      },
    );
  }
}

class _DetailsContent extends StatelessWidget {
  const _DetailsContent({required this.details});
  final MediaDetails details;

  @override
  Widget build(BuildContext context) {
    final media = details.media;
    final size = MediaQuery.sizeOf(context);
    // A 16:9 backdrop plus room for the label, capped so the header never eats
    // a short screen and never turns into a banner on a tablet.
    final headerHeight = (size.width * 9 / 16 + 70)
        .clamp(200.0, math.max(200.0, math.min(size.height * .45, 420.0)))
        .toDouble();
    // The backdrop is full-bleed, so the body has to reach the same edges or
    // the page reads as two layouts stacked on each other: a banner across the
    // whole tablet and a phone-width column adrift in the middle of it. Only
    // the prose below takes a width of its own, where line length matters.
    final sidePadding = size.width >= 600 ? 32.0 : 16.0;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: headerHeight,
          title: Text(
            media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                NetworkArtwork(
                  url: AppConfig.backdrop(media.backdropPath),
                  icon: media.type == MediaType.movie
                      ? Icons.movie_outlined
                      : Icons.live_tv_outlined,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x22080808), AppColors.midnight],
                      stops: [.3, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: sidePadding,
                  right: sidePadding,
                  bottom: 54,
                  child: ViewfinderLabel(
                    label: media.type == MediaType.movie
                        ? 'Feature film'
                        : 'Series',
                    active: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(sidePadding, 18, sidePadding, 36),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _TitleDeck(details: details),
              if (details.genres.isNotEmpty) ...[
                const SizedBox(height: 20),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: details.genres
                      .map((genre) => SoftChip(label: genre))
                      .toList(growable: false),
                ),
              ],
              if (media.overview.isNotEmpty) ...[
                const SizedBox(height: 22),
                const ViewfinderLabel(label: 'About'),
                const SizedBox(height: 9),
                // Long prose is the one thing a tablet's full width hurts:
                // the eye loses the line it is on somewhere past this.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Text(
                    media.overview,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
              if (details.cast.isNotEmpty) ...[
                const Divider(height: 36),
                Text('Top cast', style: AppTheme.display(27)),
                const SizedBox(height: 14),
                _CastRail(cast: details.cast),
              ],
              if (details.recommendations.isNotEmpty) ...[
                const Divider(height: 44),
                MediaRail(
                  title: 'You might also like',
                  items: details.recommendations,
                  type: media.type,
                  onTap: (item) => openMediaDetails(context, item),
                ),
              ],
              const SizedBox(height: 28),
              const Text(
                'This product uses the TMDB API but is not endorsed or certified by TMDB.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _TitleDeck extends StatelessWidget {
  const _TitleDeck({required this.details});
  final MediaDetails details;

  @override
  Widget build(BuildContext context) {
    final media = details.media;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // The poster tracks the available width instead of a fixed 112, so the
        // title always keeps a readable column next to it.
        final posterWidth = (width * .3).clamp(88.0, 150.0);
        final titleSize = switch (width) {
          < 320 => 21.0,
          < 380 => 24.0,
          < 520 => 27.0,
          _ => 32.0,
        };
        final stackButtons = width < 380;

        final actions = [
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerView(details: details),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('WATCH NOW'),
          ),
          if (details.trailerKey != null)
            OutlinedButton.icon(
              onPressed: () => _openTrailer(context),
              icon: const Icon(Icons.smart_display_outlined),
              label: const Text('TRAILER'),
            ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: posterWidth,
                    height: posterWidth * 1.5,
                    child: NetworkArtwork(
                      url: AppConfig.poster(media.posterPath),
                      icon: media.type == MediaType.movie
                          ? Icons.movie_outlined
                          : Icons.live_tv_outlined,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        media.title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.display(titleSize),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          SoftChip(label: _yearLabel()),
                          SoftChip(
                            label: '${media.rating.toStringAsFixed(1)} / 10',
                            icon: Icons.star_rounded,
                          ),
                          SoftChip(label: _lengthLabel()),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Buttons live under the deck so a long title can never squeeze
            // them into a sliver of unreadable, overflowing labels.
            if (stackButtons)
              Column(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: actions[i]),
                  ],
                ],
              )
            else
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }

  String _yearLabel() {
    final first = details.media.year;
    if (details.media.type == MediaType.movie ||
        details.lastAirDate.length < 4) {
      return first;
    }
    return '$first–${details.lastAirDate.substring(0, 4)}';
  }

  String _lengthLabel() {
    if (details.media.type == MediaType.movie) {
      return details.runtime == null ? 'Runtime N/A' : '${details.runtime} min';
    }
    return '${details.seasons ?? 0} seasons · ${details.episodes ?? 0} episodes';
  }

  Future<void> _openTrailer(BuildContext context) async {
    final uri = Uri.parse(
      'https://www.youtube.com/watch?v=${details.trailerKey}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the trailer.')),
      );
    }
  }
}

class _CastRail extends StatelessWidget {
  const _CastRail({required this.cast});
  final List<CastMember> cast;

  @override
  Widget build(BuildContext context) {
    // Accessibility text sizes grow the two labels under each portrait; give
    // the rail the height they actually need instead of clipping them.
    final textScaler = MediaQuery.textScalerOf(context);
    final labelHeight = textScaler.scale(11) * 1.4 + textScaler.scale(9) * 1.4;
    final height = (82 + 20 + 8 + labelHeight).clamp(154.0, 230.0);

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cast.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _CastCard(person: cast[index]),
      ),
    );
  }
}

class _CastCard extends StatelessWidget {
  const _CastCard({required this.person});
  final CastMember person;

  @override
  Widget build(BuildContext context) => Container(
    width: 112,
    padding: const EdgeInsets.all(10),
    decoration: const ShapeDecoration(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    child: Column(
      children: [
        ClipPath(
          clipper: const ShapeBorderClipper(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
          ),
          child: SizedBox(
            width: 82,
            height: 82,
            child: NetworkArtwork(
              url: AppConfig.poster(person.profilePath, size: 'w185'),
              icon: Icons.person_outline_rounded,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: Text(
            person.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        if (person.character.isNotEmpty)
          Flexible(
            child: Text(
              'as ${person.character}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 9),
            ),
          ),
      ],
    ),
  );
}
