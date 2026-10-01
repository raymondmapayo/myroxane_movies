import 'package:flutter/foundation.dart';

import '../../domain/usecases/media_usecases.dart';
import 'view_state.dart';

class HomeViewModel extends ChangeNotifier with ViewState {
  HomeViewModel(this._getHomeFeed);

  final GetHomeFeed _getHomeFeed;
  HomeFeed? feed;

  Future<void> load() async {
    status = ViewStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      feed = await _getHomeFeed();
      status = ViewStatus.ready;
    } catch (error) {
      errorMessage = friendlyError(error);
      status = ViewStatus.error;
    }
    notifyListeners();
  }
}
