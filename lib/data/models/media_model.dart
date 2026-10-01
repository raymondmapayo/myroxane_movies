import '../../domain/entities/media.dart';
import '../../domain/entities/media_details.dart';

abstract final class MediaMapper {
  static Media fromJson(Map<String, dynamic> json, {MediaType? fallbackType}) {
    final type = switch (json['media_type']) {
      'tv' => MediaType.tv,
      'movie' => MediaType.movie,
      _ =>
        fallbackType ??
            (json['title'] != null ? MediaType.movie : MediaType.tv),
    };
    return Media(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? json['name'] ?? 'Untitled') as String,
      type: type,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String? ?? '',
      rating: (json['vote_average'] as num?)?.toDouble() ?? 0,
      date: (json['release_date'] ?? json['first_air_date'] ?? '') as String,
    );
  }

  static MediaPage pageFromJson(Map<String, dynamic> json, {MediaType? type}) {
    final results = (json['results'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((item) => item['media_type'] != 'person')
        .map((item) => fromJson(item, fallbackType: type))
        .toList(growable: false);
    return MediaPage(
      items: results,
      page: (json['page'] as num?)?.toInt() ?? 1,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalResults: (json['total_results'] as num?)?.toInt() ?? results.length,
    );
  }

  static MediaDetails detailsFromJson(
    Map<String, dynamic> json,
    MediaType type,
  ) {
    final videos =
        ((json['videos'] as Map<String, dynamic>?)?['results']
                    as List<dynamic>? ??
                const [])
            .whereType<Map<String, dynamic>>();
    String? trailerKey;
    for (final video in videos) {
      if (video['site'] == 'YouTube' &&
          (video['type'] == 'Trailer' || video['type'] == 'Teaser')) {
        trailerKey = video['key'] as String?;
        break;
      }
    }

    final castJson =
        ((json['credits'] as Map<String, dynamic>?)?['cast']
            as List<dynamic>? ??
        const []);
    // Films carry `imdb_id` on the details payload itself; series only expose
    // it through the appended external ids.
    final externalIds = json['external_ids'] as Map<String, dynamic>?;
    final imdbId = (json['imdb_id'] ?? externalIds?['imdb_id']) as String?;

    final recsJson =
        ((json['recommendations'] as Map<String, dynamic>?)?['results']
            as List<dynamic>? ??
        const []);
    return MediaDetails(
      media: fromJson(json, fallbackType: type),
      voteCount: (json['vote_count'] as num?)?.toInt() ?? 0,
      runtime: (json['runtime'] as num?)?.toInt(),
      seasons: (json['number_of_seasons'] as num?)?.toInt(),
      episodes: (json['number_of_episodes'] as num?)?.toInt(),
      lastAirDate: json['last_air_date'] as String? ?? '',
      genres: (json['genres'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((genre) => genre['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false),
      countries: (json['production_countries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((country) => country['name'] as String? ?? '')
          .where((name) => name.isNotEmpty)
          .toList(growable: false),
      cast: castJson
          .whereType<Map<String, dynamic>>()
          .take(10)
          .map(
            (person) => CastMember(
              id: (person['id'] as num?)?.toInt() ?? 0,
              name: person['name'] as String? ?? 'Unknown',
              character: person['character'] as String? ?? '',
              profilePath: person['profile_path'] as String?,
            ),
          )
          .toList(growable: false),
      seasonList: (json['seasons'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(
            (season) => Season(
              number: (season['season_number'] as num?)?.toInt() ?? 0,
              episodeCount: (season['episode_count'] as num?)?.toInt() ?? 0,
              name: season['name'] as String? ?? 'Season',
            ),
          )
          .where((season) => season.number >= 1 && season.episodeCount > 0)
          .toList(growable: false),
      recommendations: recsJson
          .whereType<Map<String, dynamic>>()
          .take(12)
          .map((item) => fromJson(item, fallbackType: type))
          .toList(growable: false),
      trailerKey: trailerKey,
      imdbId: (imdbId != null && imdbId.startsWith('tt')) ? imdbId : null,
    );
  }
}
