import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/media.dart';

class NetworkArtwork extends StatelessWidget {
  const NetworkArtwork({
    super.key,
    required this.url,
    required this.icon,
    this.fit = BoxFit.cover,
  });

  final String url;
  final IconData icon;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _fallback();
    return Image.network(
      url,
      fit: fit,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, _) => AnimatedOpacity(
        opacity: frame == null ? 0 : 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        child: child,
      ),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(color: AppColors.raised),
      errorBuilder: (_, _, _) => _fallback(),
    );
  }

  Widget _fallback() => ColoredBox(
    color: AppColors.raised,
    child: Center(
      child: Icon(
        icon,
        color: AppColors.muted.withValues(alpha: .65),
        size: 42,
      ),
    ),
  );
}

class LantawMark extends StatelessWidget {
  const LantawMark({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(compact ? 5 : 6),
        child: Image.asset(
          'assets/brand/lantaw-mark.png',
          width: compact ? 24 : 29,
          height: compact ? 24 : 29,
          filterQuality: FilterQuality.high,
        ),
      ),
      const SizedBox(width: 9),
      Text('LANTAW', style: AppTheme.display(compact ? 17 : 20)),
    ],
  );
}

class ViewfinderLabel extends StatelessWidget {
  const ViewfinderLabel({super.key, required this.label, this.active = false});
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Text(
    label.toUpperCase(),
    style: AppTheme.utility(
      size: 10,
      color: active ? AppColors.projector : AppColors.muted,
      weight: FontWeight.w700,
    ),
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    this.detail,
  });

  final String eyebrow;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ViewfinderLabel(label: eyebrow, active: true),
      const SizedBox(height: 8),
      Text(title, style: AppTheme.display(28)),
      if (detail != null) ...[
        const SizedBox(height: 8),
        Text(
          detail!,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    ],
  );
}

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.media, required this.onTap});

  final Media media;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Open ${media.title}',
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetworkArtwork(
              url: AppConfig.poster(media.posterPath, size: 'w342'),
              icon: media.type == MediaType.movie
                  ? Icons.movie_outlined
                  : Icons.live_tv_outlined,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x09080808),
                    Color(0x22080808),
                    Color(0xF5080808),
                  ],
                  stops: [0, .47, 1],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    media.year,
                    style: AppTheme.utility(size: 9, color: AppColors.muted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    media.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                    ),
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

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    required this.type,
    this.count,
  });

  final String title;
  final MediaType type;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: Text(title, style: AppTheme.display(20))),
      if (count != null)
        Text(
          '$count titles',
          style: AppTheme.utility(size: 9, color: AppColors.muted),
        ),
    ],
  );
}

class SoftChip extends StatelessWidget {
  const SoftChip({super.key, required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 30),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: const ShapeDecoration(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: AppColors.amber),
          const SizedBox(width: 5),
        ],
        // A long label (a season/episode count, a wordy genre) has to shrink
        // inside a narrow column instead of overflowing its row.
        Flexible(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.utility(size: 8.5),
          ),
        ),
      ],
    ),
  );
}

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    required this.type,
  });

  final String title;
  final List<Media> items;
  final MediaType type;
  final ValueChanged<Media> onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeading(title: title, type: type, count: items.length),
      const SizedBox(height: 16),
      SizedBox(
        height: 226,
        child: ListView.separated(
          clipBehavior: Clip.none,
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 11),
          itemBuilder: (context, index) => SizedBox(
            width: 140,
            child: MediaCard(
              media: items[index],
              onTap: () => onTap(items[index]),
            ),
          ),
        ),
      ),
    ],
  );
}

class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Media> items;
  final ValueChanged<Media> onTap;
  final EdgeInsets padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 900
          ? 5
          : constraints.maxWidth >= 620
          ? 4
          : 2;
      return GridView.builder(
        padding: padding,
        shrinkWrap: shrinkWrap,
        physics: physics,
        itemCount: items.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 11,
          mainAxisSpacing: 11,
          childAspectRatio: .66,
        ),
        itemBuilder: (context, index) =>
            MediaCard(media: items[index], onTap: () => onTap(items[index])),
      );
    },
  );
}
