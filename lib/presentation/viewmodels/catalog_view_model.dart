import 'package:flutter/foundation.dart';

import '../../domain/entities/media.dart';
import '../../domain/usecases/media_usecases.dart';
import 'view_state.dart';

class CatalogViewModel extends ChangeNotifier with ViewState {
  CatalogViewModel(this._discover, {required this.type});

  final DiscoverMedia _discover;
  MediaType type;
  int? genre;
  String? language;
  List<Media> items = const [];
  int page = 1;
  int totalPages = 1;
  int totalResults = 0;
  bool isLoadingMore = false;

  Future<void> load({bool reset = true}) async {
    if (reset) {
      status = ViewStatus.loading;
      errorMessage = null;
      page = 1;
      notifyListeners();
    }
    try {
      final result = await _discover(
        type,
        page: page,
        genre: genre,
        language: language,
      );
      items = reset ? result.items : [...items, ...result.items];
      totalPages = result.totalPages;
      totalResults = result.totalResults;
      status = items.isEmpty ? ViewStatus.empty : ViewStatus.ready;
    } catch (error) {
      errorMessage = friendlyError(error);
      status = ViewStatus.error;
    }
    isLoadingMore = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (isLoadingMore || page >= totalPages || status != ViewStatus.ready) {
      return;
    }
    isLoadingMore = true;
    page += 1;
    notifyListeners();
    await load(reset: false);
  }

  Future<void> updateFilters({
    MediaType? type,
    int? genre,
    bool clearGenre = false,
    String? language,
    bool clearLanguage = false,
  }) async {
    this.type = type ?? this.type;
    this.genre = clearGenre ? null : genre ?? this.genre;
    this.language = clearLanguage ? null : language ?? this.language;
    await load();
  }
}
