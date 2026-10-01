abstract final class AppConfig {
  static const tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const tmdbImageBaseUrl = 'https://image.tmdb.org/t/p';
  static const tmdbToken = String.fromEnvironment('TMDB_V4_TOKEN');

  static String poster(String? path, {String size = 'w500'}) =>
      path == null || path.isEmpty ? '' : '$tmdbImageBaseUrl/$size$path';

  static String backdrop(String? path) =>
      path == null || path.isEmpty ? '' : '$tmdbImageBaseUrl/w1280$path';
}
