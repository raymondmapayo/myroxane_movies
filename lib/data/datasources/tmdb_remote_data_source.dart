import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class TmdbRemoteDataSource {
  TmdbRemoteDataSource(this._client);

  final http.Client _client;

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    if (AppConfig.tmdbToken.isEmpty) {
      throw const TmdbConfigurationException();
    }
    final uri = Uri.parse('${AppConfig.tmdbBaseUrl}/$path')
        .replace(queryParameters: {'language': 'en-US', ...query});
    final response = await _client.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${AppConfig.tmdbToken}',
        'accept': 'application/json',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TmdbRequestException(response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class TmdbConfigurationException implements Exception {
  const TmdbConfigurationException();

  @override
  String toString() => 'TMDB token is missing. Start with tool/run_lantaw.sh.';
}

class TmdbRequestException implements Exception {
  const TmdbRequestException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'TMDB request failed ($statusCode).';
}
