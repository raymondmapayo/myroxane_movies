import 'media.dart';

class CastMember {
  const CastMember({
    required this.id,
    required this.name,
    this.character = '',
    this.profilePath,
  });

  final int id;
  final String name;
  final String character;
  final String? profilePath;
}

class Season {
  const Season({
    required this.number,
    required this.episodeCount,
    required this.name,
  });

  final int number;
  final int episodeCount;
  final String name;
}

class MediaDetails {
  const MediaDetails({
    required this.media,
    required this.voteCount,
    required this.genres,
    required this.countries,
    required this.cast,
    required this.seasonList,
    required this.recommendations,
    this.runtime,
    this.seasons,
    this.episodes,
    this.lastAirDate = '',
    this.trailerKey,
    this.imdbId,
  });

  final Media media;
  final int voteCount;
  final List<String> genres;
  final List<String> countries;
  final List<CastMember> cast;
  final List<Season> seasonList;
  final List<Media> recommendations;
  final int? runtime;
  final int? seasons;
  final int? episodes;
  final String lastAirDate;
  final String? trailerKey;

  /// Mirrors that index by IMDb id need this; TMDB does not have one for every
  /// title, so it stays nullable.
  final String? imdbId;
}
