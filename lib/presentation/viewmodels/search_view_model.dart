import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/media.dart';
import '../../domain/usecases/media_usecases.dart';
import 'view_state.dart';

class SearchViewModel extends ChangeNotifier with ViewState {
  SearchViewModel(this._search);

  final SearchMedia _search;
  Timer? _debounce;
  String query = '';
  List<Media> results = const [];

  void updateQuery(String value) {
    query = value.trim();
    _debounce?.cancel();
    if (query.isEmpty) {
      results = const [];
      status = ViewStatus.idle;
      notifyListeners();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => search(query));
  }

  Future<void> search(String value) async {
    final requestedQuery = value.trim();
    if (requestedQuery.isEmpty) return;
    query = requestedQuery;
    status = ViewStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      final page = await _search(requestedQuery);
      if (requestedQuery != query) return;
      results = page.items;
      status = results.isEmpty ? ViewStatus.empty : ViewStatus.ready;
    } catch (error) {
      errorMessage = friendlyError(error);
      status = ViewStatus.error;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
