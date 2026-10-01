import '../../domain/entities/media.dart';

/// Everything a mirror needs to address one title: both ids TMDB knows the
/// title by, the episode for series, and the viewer's autoplay preference.
typedef PlayerRequest = ({
  int mediaId,
  String? imdbId,
  int season,
  int episode,
  bool autoPlay,
});

PlayerRequest playerRequest({
  required int mediaId,
  String? imdbId,
  int season = 1,
  int episode = 1,
  bool autoPlay = true,
}) => (
  mediaId: mediaId,
  imdbId: imdbId,
  season: season,
  episode: episode,
  autoPlay: autoPlay,
);

class PlayerSource {
  const PlayerSource({
    required this.id,
    required this.label,
    required this.host,
    required this.buildUrl,
    this.needsImdbId = false,
  });

  final String id;
  final String label;
  final String host;

  /// Some mirrors index by IMDb id rather than TMDB id, so they cannot play a
  /// title TMDB has no IMDb id for. Those drop out of the picker and out of
  /// the automatic fallback chain instead of loading a dead embed.
  final bool needsImdbId;

  /// Mirrors take their playback preferences as query parameters, so the URL
  /// has to be rebuilt whenever autoplay is toggled.
  final String Function(PlayerRequest request) buildUrl;

  bool supports(PlayerRequest request) =>
      !needsImdbId || (request.imdbId?.isNotEmpty ?? false);

  bool matchesPlayerUrl(Uri url, PlayerRequest request) {
    if (!supports(request)) return false;
    final expected = Uri.parse(buildUrl(request));
    final normalizedHost = url.host.toLowerCase();
    final matchesHost =
        normalizedHost == host || normalizedHost.endsWith('.$host');
    // Only the path and the episode identify the title; the autoplay and
    // poster parameters do not.
    return matchesHost &&
        url.path == expected.path &&
        _episodeParams(url) == _episodeParams(expected);
  }

  /// Mirrors that keep the episode in the query string rather than the path
  /// would otherwise look identical for every episode of a series.
  static ({String? season, String? episode}) _episodeParams(Uri url) =>
      (season: url.queryParameters['s'], episode: url.queryParameters['e']);
}

abstract final class PlayerSources {
  static final movie = <PlayerSource>[
    PlayerSource(
      id: 'mirror-1',
      label: 'Mirror 1',
      host: 'vidlink.pro',
      buildUrl: (request) =>
          'https://vidlink.pro/movie/${request.mediaId}'
          '?autoplay=${request.autoPlay}',
    ),
    PlayerSource(
      id: 'mirror-2',
      label: 'Mirror 2',
      host: 'vidsrc.to',
      buildUrl: (request) =>
          'https://vidsrc.to/embed/movie/${request.mediaId}'
          '?autoplay=${request.autoPlay ? 1 : 0}',
    ),
    PlayerSource(
      id: 'mirror-3',
      label: 'Mirror 3',
      host: 'cinesrc.st',
      buildUrl: (request) =>
          'https://cinesrc.st/embed/movie/${request.mediaId}',
    ),
    PlayerSource(
      id: 'mirror-4',
      label: 'Mirror 4',
      host: 'vidsrc.cc',
      needsImdbId: true,
      buildUrl: (request) =>
          'https://vidsrc.cc/v2/embed/movie/${request.imdbId}'
          '?poster=true&autoPlay=false',
    ),
  ];

  static final tv = <PlayerSource>[
    PlayerSource(
      id: 'mirror-1',
      label: 'Mirror 1',
      host: 'vidlink.pro',
      buildUrl: (request) =>
          'https://vidlink.pro/tv/${request.mediaId}'
          '/${request.season}/${request.episode}'
          '?autoplay=${request.autoPlay}&nextbutton=true',
    ),
    PlayerSource(
      id: 'mirror-2',
      label: 'Mirror 2',
      host: 'cinesrc.st',
      buildUrl: (request) =>
          'https://cinesrc.st/embed/tv/${request.mediaId}'
          '?s=${request.season}&e=${request.episode}',
    ),
    PlayerSource(
      id: 'mirror-3',
      label: 'Mirror 3',
      host: 'vidsrc.to',
      buildUrl: (request) =>
          'https://vidsrc.to/embed/tv/${request.mediaId}'
          '/${request.season}/${request.episode}'
          '?autoplay=${request.autoPlay ? 1 : 0}',
    ),
    PlayerSource(
      id: 'mirror-4',
      label: 'Mirror 4',
      host: 'vidsrc.cc',
      needsImdbId: true,
      buildUrl: (request) =>
          'https://vidsrc.cc/v2/embed/tv/${request.imdbId}'
          '/${request.season}/${request.episode}'
          '?poster=true&autoPlay=false',
    ),
  ];

  static List<PlayerSource> forType(MediaType type) =>
      type == MediaType.movie ? movie : tv;

  /// The mirrors that can actually address this title, in picker order.
  static List<PlayerSource> availableFor(MediaType type, {String? imdbId}) {
    final request = playerRequest(mediaId: 0, imdbId: imdbId);
    return forType(type)
        .where((source) => source.supports(request))
        .toList(growable: false);
  }

  /// The mirror a title opens on. The others stay available in the picker and
  /// in the automatic fallback chain, so this only decides the first attempt.
  static PlayerSource preferredFor(MediaType type, {String? imdbId}) {
    final sources = availableFor(type, imdbId: imdbId);
    return sources.firstWhere(
      (source) => source.id == 'mirror-1',
      orElse: () => sources.first,
    );
  }
}
