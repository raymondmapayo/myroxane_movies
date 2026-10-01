import 'package:flutter/foundation.dart';

import '../../domain/entities/media.dart';
import '../../domain/entities/media_details.dart';
import '../../domain/usecases/media_usecases.dart';
import 'view_state.dart';

class DetailsViewModel extends ChangeNotifier with ViewState {
  DetailsViewModel(this._getDetails, {required this.type, required this.id});

  final GetMediaDetails _getDetails;
  final MediaType type;
  final int id;
  MediaDetails? details;

  Future<void> load() async {
    status = ViewStatus.loading;
    errorMessage = null;
    notifyListeners();
    try {
      details = await _getDetails(type, id);
      status = ViewStatus.ready;
    } catch (error) {
      errorMessage = friendlyError(error);
      status = ViewStatus.error;
    }
    notifyListeners();
  }
}
