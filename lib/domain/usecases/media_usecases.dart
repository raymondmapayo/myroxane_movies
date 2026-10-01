import '../entities/media.dart';
import '../entities/media_details.dart';
import '../repositories/media_repository.dart';

class HomeFeed {
  const HomeFeed({
    required this.popularMovies,
    required this.popularSeries,
    required this.highRatedMovies,
  });

  final List<Media> popularMovies;
  final List<Media> popularSeries;
  final List<Media> highRatedMovies;

  Media? get spotlight =>
      popularMovies.firstOrNull ?? popularSeries.firstOrNull;
}

class GetHomeFeed {
  const GetHomeFeed(this._repository);
  final MediaRepository _repository;

  Future<HomeFeed> call() async {
    final values = await Future.wait([
      _repository.discover(MediaType.movie),
      _repository.discover(MediaType.tv),
      _repository.discover(
        MediaType.movie,
        sortBy: 'vote_average.desc',
        minimumVotes: 600,
      ),
    ]);
    return HomeFeed(
      popularMovies: values[0].items.take(12).toList(growable: false),
      popularSeries: values[1].items.take(12).toList(growable: false),
      highRatedMovies: values[2].items.take(12).toList(growable: false),
    );
  }
}

class DiscoverMedia {
  const DiscoverMedia(this._repository);
  final MediaRepository _repository;

  Future<MediaPage> call(
    MediaType type, {
    int page = 1,
    int? genre,
    String? language,
  }) =>
      _repository.discover(type, page: page, genre: genre, language: language);
}

class SearchMedia {
  const SearchMedia(this._repository);
  final MediaRepository _repository;

  Future<MediaPage> call(String query, {int page = 1}) =>
      _repository.search(query, page: page);
}

class GetMediaDetails {
  const GetMediaDetails(this._repository);
  final MediaRepository _repository;

  Future<MediaDetails> call(MediaType type, int id) =>
      _repository.details(type, id);
}
