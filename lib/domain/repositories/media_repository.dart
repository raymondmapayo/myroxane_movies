import '../entities/media.dart';
import '../entities/media_details.dart';

abstract interface class MediaRepository {
  Future<MediaPage> discover(
    MediaType type, {
    int page = 1,
    String sortBy = 'popularity.desc',
    int? genre,
    String? language,
    int? minimumVotes,
  });

  Future<MediaPage> search(String query, {int page = 1});

  Future<MediaDetails> details(MediaType type, int id);
}
