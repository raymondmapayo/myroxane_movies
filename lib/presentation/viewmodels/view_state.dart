enum ViewStatus { idle, loading, ready, empty, error }

mixin ViewState {
  ViewStatus status = ViewStatus.idle;
  String? errorMessage;

  String friendlyError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '');
    return message.isEmpty
        ? 'Something went wrong. Please try again.'
        : message;
  }
}
