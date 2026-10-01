enum MediaType { movie, tv }

extension MediaTypeX on MediaType {
  String get apiValue => this == MediaType.movie ? 'movie' : 'tv';
  String get label => this == MediaType.movie ? 'Movie' : 'Series';
}

class Media {
  const Media({
    required this.id,
    required this.title,
    required this.type,
    this.posterPath,
    this.backdropPath,
    this.overview = '',
    this.rating = 0,
    this.date = '',
  });

  final int id;
  final String title;
  final MediaType type;
  final String? posterPath;
  final String? backdropPath;
  final String overview;
  final double rating;
  final String date;

  String get year => date.length >= 4 ? date.substring(0, 4) : 'TBA';
}

class MediaPage {
  const MediaPage({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalResults,
  });

  final List<Media> items;
  final int page;
  final int totalPages;
  final int totalResults;
}
