import '../../domain/entities/media.dart';
import '../../domain/entities/media_details.dart';
import '../../domain/repositories/media_repository.dart';
import '../datasources/tmdb_remote_data_source.dart';
import '../models/media_model.dart';

class TmdbMediaRepository implements MediaRepository {
  const TmdbMediaRepository(this._remote);

  final TmdbRemoteDataSource _remote;

  @override
  Future<MediaPage> discover(
    MediaType type, {
    int page = 1,
    String sortBy = 'popularity.desc',
    int? genre,
    String? language,
    int? minimumVotes,
  }) async {
    final json = await _remote.get('discover/${type.apiValue}', {
      'page': '$page',
      'sort_by': sortBy,
      'include_adult': 'false',
      if (genre != null) 'with_genres': '$genre',
      if (language != null && language.isNotEmpty)
        'with_original_language': language,
      if (minimumVotes != null) 'vote_count.gte': '$minimumVotes',
    });
    return MediaMapper.pageFromJson(json, type: type);
  }

  @override
  Future<MediaPage> search(String query, {int page = 1}) async {
    final json = await _remote.get('search/multi', {
      'query': query,
      'page': '$page',
      'include_adult': 'false',
    });
    return MediaMapper.pageFromJson(json);
  }

  @override
  Future<MediaDetails> details(MediaType type, int id) async {
    final json = await _remote.get('${type.apiValue}/$id', {
      'append_to_response': 'credits,videos,recommendations,external_ids',
    });
    return MediaMapper.detailsFromJson(json, type);
  }
}
